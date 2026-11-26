"""Reads simulated games and asks a local model where a computer player did
something it should not have, then sums the findings up by kind and role.

1. Export games (every seat a computer, each with its reasons):
     BALANCE_GAMES=40 BALANCE_TALK=on BALANCE_REVIEW=build/llm/games.jsonl ^
       flutter test test/balance_test.dart
2. Read them (minutes a game on a CPU; stops and picks up where it was):
     python tool/llm/analyze_games.py build/llm/games.jsonl
3. build/llm/report.md: what went wrong most often, with examples.

The model only points; every finding is checked by a person against the
bots' code (lib/features/solo/) before anything is changed.
"""
import argparse
import collections
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import llm  # noqa: E402

SYSTEM = """你是阿瓦隆（The Resistance: Avalon）的資深玩家兼 AI 對手的審查員。
你會讀到一局「所有座位都是電腦」的完整復盤（1號「玩家」也是電腦），找出電腦明顯不合理的決定。

規則重點：
- 正義方要完成三次任務；邪惡方要讓三次任務失敗，或在正義三勝後由刺客刺中梅林。
- 梅林看得到邪惡（莫德雷德除外），但不能暴露自己；派西維爾看到梅林和莫甘娜（分不出誰是誰）。
- 邪惡方彼此認得（奧伯倫除外）。正義玩家出任務只能出成功；邪惡可以出失敗。
- 連續五次提案被否決，邪惡直接獲勝；所以第五次提案（提案5）正義方通常要贊成。
- 7 人以上第四次任務要兩張失敗才算失敗。

復盤格式：
- 「== 身分」是真實身分，只有你看得到；每位電腦當下只知道自己身分能知道的資訊與公開紀錄。
- 每次提案列出發言（［台詞 ID］或［引用紀錄］等是台詞來源，（挺）（反）是表態，→懷疑N號 是點名），
  再列出投票：○贊成 ✕反對，後面是那台電腦自己的理由。
- 「原本出的牌：2成 5敗」是每人出的任務牌。

判斷原則：
- 只用那台電腦「當下能知道的資訊」評斷，不要用事後才知道的真實身分苛責它。
- 邪惡刻意偽裝、梅林刻意隱藏，是合理策略，不算錯；除非做法明顯會害自己陣營。
- 只挑真正明顯、對局勢有影響的錯誤，寧缺勿濫；沒有就回傳空清單。
- 發言前後矛盾、說出不該知道的資訊、正義投票明顯違背公開紀錄、隊長帶明顯可疑的人、
  刺客忽略明顯線索、第五次提案正義反對，都是值得指出的類型。

一次只會給你一次遠征（或結局）的詳細紀錄，加上身分與之前各次的結果；只評這一段裡的決定。

只回傳 JSON：{"issues": [{"seat": 座位號碼(數字), "where": "第N次遠征 提案M 或 結局",
"kind": "投票|發言|組隊|出牌|刺殺|湖中女神|王者之劍|其他",
"quote": "從紀錄中原封不動複製、能證明這個決定的那一行（例如投票行「3✕　嫌疑或隊伍風險超過接受範圍」或發言行）",
"what": "它做了什麼", "why": "依它當下能知道的資訊，為什麼不合理", "better": "比較合理的做法", "severity": 1到3}]}
severity：3 直接影響勝負，2 明顯失誤，1 小瑕疵。全部用繁體中文。"""


def sections(text: str):
    """(name, prompt) for each quest and the end: the identities, the results
    so far, then that part of the record in full."""
    head, _, body = text.partition("== 第1次遠征")
    identities = "== 身分" + head.split("== 身分", 1)[-1].split("== 你的表現", 1)[0]
    parts = re.split(r"(?m)^(== .+)$", "== 第1次遠征" + body)
    results = []
    for i in range(1, len(parts), 2):
        name, detail = parts[i].strip("= ").strip(), parts[i + 1]
        so_far = "\n".join(results) or "（尚無）"
        yield name, f"{identities}\n== 之前的結果\n{so_far}\n\n== {name}\n{detail}"
        results += [f"{name}：{l.strip()}" for l in detail.splitlines() if l.startswith(">>")]


def checked(issue, text: str) -> bool:
    """The model quoted the record: the line it points to is really there,
    for the seat it names (a vote quoted with the wrong mark is dropped)."""
    quote = re.sub(r"\s+", "", str(issue.get("quote", "")))
    if len(quote) < 4:
        return False
    lines = [re.sub(r"\s+", "", l) for l in text.splitlines()]
    hits = [l for l in lines if quote in l or (len(l) > 6 and l in quote)]
    if not hits:
        return False
    seat = str(issue.get("seat", ""))
    return any(l.startswith(seat) or f"{seat}號" in l for l in hits)


def roles_of(text: str) -> dict:
    """Seat number → (role, side) from the review's 身分 section."""
    roles = {}
    part = text.split("== 身分", 1)[-1].split("==", 1)[0]
    for line in part.splitlines():
        m = re.match(r"(\d+)號[^：]*：([^（]+)（(正義|邪惡)", line.strip())
        if m:
            roles[int(m.group(1))] = (m.group(2), m.group(3))
    return roles


def analyze(games: Path, out: Path, limit: int | None):
    out.mkdir(parents=True, exist_ok=True)
    found = out / "findings.jsonl"
    done = set()
    if found.exists():
        for line in found.read_text(encoding="utf-8").splitlines():
            done.add(json.loads(line)["game"])
    rows = [json.loads(l) for l in games.read_text(encoding="utf-8").splitlines() if l.strip()]
    if limit:
        rows = rows[:limit]
    todo = [r for r in rows if r["game"] not in done]
    print(f"{len(rows)} games, {len(done)} read before, {len(todo)} to read with {llm.MODEL}")
    with found.open("a", encoding="utf-8") as sink:
        for i, row in enumerate(todo, 1):
            issues, dropped = [], 0
            for name, prompt in sections(row["text"]):
                answer = llm.ask(SYSTEM, prompt, json_mode=True,
                                 # room for a reasoning model's thinking too
                                 context=min(8192 + len(prompt) * 2, 24576))
                for issue in answer.get("issues", []) if isinstance(answer, dict) else []:
                    if isinstance(issue, dict) and checked(issue, row["text"]):
                        issues.append(issue)
                    else:
                        dropped += 1
            sink.write(json.dumps({"game": row["game"], "n": row["n"], "exp": row["exp"],
                                   "issues": issues, "dropped": dropped}, ensure_ascii=False) + "\n")
            sink.flush()
            print(f"  [{i}/{len(todo)}] game {row['game']}: {len(issues)} findings"
                  f" ({dropped} dropped: quote not in the record)", flush=True)
    report(rows, found, out / "report.md")


def report(rows, found: Path, path: Path):
    texts = {r["game"]: r["text"] for r in rows}
    findings = [json.loads(l) for l in found.read_text(encoding="utf-8").splitlines()]
    by_kind = collections.Counter()
    by_role = collections.Counter()
    serious = []
    examples = collections.defaultdict(list)
    for game in findings:
        roles = roles_of(texts.get(game["game"], ""))
        for issue in game["issues"]:
            try:
                seat = int(issue.get("seat", 0))
                severity = int(issue.get("severity", 1))
            except (TypeError, ValueError):
                continue
            role, side = roles.get(seat, ("?", "?"))
            kind = issue.get("kind", "其他")
            by_kind[kind] += 1
            by_role[f"{role}（{side}）"] += 1
            entry = (severity, game["game"], seat, role, issue)
            examples[kind].append(entry)
            if severity >= 3:
                serious.append(entry)
    lines = [f"# 電腦對局審查（{len(findings)} 局，模型 {llm.MODEL}）", "",
             "模型只負責指出可疑之處，每一條都要對照 lib/features/solo/ 的程式確認後才修改。",
             f"引用的原文在紀錄裡找不到（多半是模型看錯）而剔除的："
             f"{sum(g.get('dropped', 0) for g in findings)} 條。", "",
             "## 依類型", ""]
    lines += [f"- {k}：{v}" for k, v in by_kind.most_common()]
    lines += ["", "## 依角色", ""]
    lines += [f"- {k}：{v}" for k, v in by_role.most_common()]

    def item(entry):
        severity, game, seat, role, issue = entry
        return (f"- 第 {game} 局 {seat}號（{role}）{issue.get('where', '')}，嚴重度 {severity}\n"
                f"  - 原文：{issue.get('quote', '')}\n"
                f"  - 做了：{issue.get('what', '')}\n  - 問題：{issue.get('why', '')}\n"
                f"  - 較好：{issue.get('better', '')}")

    lines += ["", "## 影響勝負的（嚴重度 3）", ""]
    lines += [item(e) for e in sorted(serious, key=lambda e: e[1])] or ["（無）"]
    for kind, _ in by_kind.most_common():
        lines += ["", f"## {kind}：例子", ""]
        lines += [item(e) for e in sorted(examples[kind], key=lambda e: -e[0])[:8]]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"report: {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("games", type=Path, help="JSON lines from BALANCE_REVIEW")
    parser.add_argument("--out", type=Path, default=Path("build/llm"))
    parser.add_argument("--limit", type=int, help="read only the first N games")
    parser.add_argument("--report-only", action="store_true", help="only rebuild report.md")
    args = parser.parse_args()
    if args.report_only:
        rows = [json.loads(l) for l in args.games.read_text(encoding="utf-8").splitlines() if l.strip()]
        report(rows, args.out / "findings.jsonl", args.out / "report.md")
    else:
        if not llm.available():
            sys.exit(f"{llm.MODEL} is not ready: start Ollama and `ollama pull {llm.MODEL}`")
        analyze(args.games, args.out, args.limit)
