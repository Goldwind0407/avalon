"""Asks a local model for more ways of saying the computers' lines, and keeps
only the ones that pass the same checks as the catalog.

    python tool/llm/dialogue.py --ids G01,G02        # these lines
    python tool/llm/dialogue.py --role merlin        # every Merlin line
    python tool/llm/dialogue.py --all --count 3      # everything (hours)

Writes build/llm/dialogue_suggestions.txt in the format of
docs/bot_dialogue_natural.txt ("ID | 說法 | 說法 …"). Nothing is added to
the game by itself: pick the lines you like, paste them into
docs/bot_dialogue_natural.txt, then run tool/prepare_bot_dialogue.py.
"""
import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import llm  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
TEMPLATES = ROOT / "docs/avalon_bot_dialogue_templates_v2.json"
NATURAL = ROOT / "docs/bot_dialogue_natural.txt"
PLACEHOLDER = re.compile(r"\{\{[^}]+\}\}")
ROLE_NAMES = {
    "all": "任何角色", "loyal_servant": "亞瑟的忠臣（正義）", "merlin": "梅林（正義，知道壞人但要藏好）",
    "percival": "派西維爾（正義）", "evil_minion": "莫德雷德的爪牙（邪惡）", "assassin": "刺客（邪惡）",
    "morgana": "莫甘娜（邪惡，假扮梅林）", "mordred": "莫德雷德（邪惡，梅林看不到）",
    "oberon": "奧伯倫（邪惡，和隊友互不相識）", "lancelot_good": "正義蘭斯洛特", "lancelot_evil": "邪惡蘭斯洛特",
}
POLICIES = {
    "public_grounded": "只能根據公開的紀錄（投票、任務結果、發言）說話，不可透露私人資訊。",
    "private_truth_claim": "說出自己真實的私人資訊（例如湖中女神的結果），必須屬實。",
    "private_strategy_public_claim": "依私人判斷行動，但說出口的理由只能引用公開紀錄。",
    "strategic_opinion_bluff": "邪惡方的偽裝發言：說法要像好人的推理，但不可聲稱看過私人資訊。",
    "intentional_opinion_bluff": "邪惡方的偽裝發言：說法要像好人的推理，但不可聲稱看過私人資訊。",
    "explicit_private_claim_lie": "邪惡方明確謊稱私人資訊（例如假跳身分），語氣要篤定。",
}
SYSTEM = """你替台灣的阿瓦隆桌遊 App 寫電腦玩家的台詞。
要求：台灣口語、自然、像真人在桌遊局裡講話；每句 8 到 40 個字；一句話一個重點。
不得加入原本說法沒有的事件、人名、座位或數字；{{...}} 是程式填入的欄位，只能使用原本說法裡出現過的欄位，原樣保留。
立場要和原本說法一致（贊成就贊成、反對就反對、懷疑就懷疑）。不要和原本說法重複或只換一兩個字。
只回傳 JSON：{"lines": ["說法", ...]}"""


def load():
    entries = {e["id"]: e for e in json.loads(TEMPLATES.read_text(encoding="utf-8"))["entries"]}
    natural = {}
    for line in NATURAL.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or "|" not in line:
            continue
        rule, *variants = [part.strip() for part in line.split("|")]
        natural[rule] = [v for v in variants if v]
    return entries, natural


def suggest(entry, existing, count):
    allowed = set(PLACEHOLDER.findall(" ".join(existing)))
    prompt = (f"角色：{ROLE_NAMES.get(entry['role'], entry['role'])}\n"
              f"時機：{entry.get('trigger', '')}\n"
              f"條件：{'、'.join(entry.get('prerequisites') or []) or '無'}\n"
              f"意圖：{entry.get('intent', '')}\n"
              f"說話規則：{POLICIES.get(entry.get('claim_policy', ''), '')}\n"
              f"可用欄位：{'、'.join(sorted(allowed)) or '（無，不可使用 {{...}}）'}\n"
              "原本的說法：\n" + "\n".join(f"- {v}" for v in existing) +
              f"\n\n請再寫 {count + 2} 種不同的說法。")
    answer = llm.ask(SYSTEM, prompt, json_mode=True, temperature=0.8)
    lines = answer.get("lines", []) if isinstance(answer, dict) else []
    kept, dropped = [], []
    seen = {re.sub(r"\W", "", v) for v in existing}
    for line in lines:
        line = str(line).strip()
        bare = re.sub(r"\W", "", line)
        if not 8 <= len(PLACEHOLDER.sub("某", line)) <= 40:
            dropped.append((line, "長度"))
        elif not set(PLACEHOLDER.findall(line)) <= allowed:
            dropped.append((line, "用了原本沒有的欄位"))
        elif bare in seen or any(bare in s or s in bare for s in seen if len(s) > 6):
            dropped.append((line, "和原本或其他說法重複"))
        elif "|" in line:
            dropped.append((line, "含有分隔符號"))
        else:
            kept.append(line)
            seen.add(bare)
    return kept[:count], dropped


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ids", help="comma-separated rule ids, e.g. G01,RME03")
    parser.add_argument("--role", help="every line of one role (merlin, assassin, all…)")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--count", type=int, default=3, help="new lines a rule")
    parser.add_argument("--out", type=Path, default=ROOT / "build/llm/dialogue_suggestions.txt")
    args = parser.parse_args()
    if not llm.available():
        sys.exit(f"{llm.MODEL} is not ready: start Ollama and `ollama pull {llm.MODEL}`")
    entries, natural = load()
    ids = (args.ids.split(",") if args.ids else
           [i for i, e in entries.items() if args.all or e["role"] == args.role])
    if not ids:
        sys.exit("say which lines: --ids, --role or --all")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    out = ["# 模型建議的新說法（未加入遊戲）。挑喜歡的貼進 docs/bot_dialogue_natural.txt 同一行。", ""]
    rejected = ["", "# 被自動檢查擋下的說法", ""]
    for n, rule in enumerate(ids, 1):
        entry = entries.get(rule)
        existing = natural.get(rule) or (entry or {}).get("templates", [])
        if not entry or not existing:
            print(f"  skip {rule}: unknown")
            continue
        kept, dropped = suggest(entry, existing, args.count)
        print(f"  [{n}/{len(ids)}] {rule}: {len(kept)} kept, {len(dropped)} dropped", flush=True)
        if kept:
            out.append(f"{rule} | " + " | ".join(kept))
        rejected += [f"{rule}　{line}　（{why}）" for line, why in dropped]
        args.out.write_text("\n".join(out + rejected) + "\n", encoding="utf-8")
    print(f"suggestions: {args.out}")


if __name__ == "__main__":
    main()
