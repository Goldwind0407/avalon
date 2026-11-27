"""Plays the same simulated games under two settings and asks a local model
what the difference in the numbers suggests. The numbers decide; the model
only reads them and proposes what to look at next.

    python tool/llm/compare_balance.py --games 300 ^
        --a "BALANCE_CLAIMS=on" --b "BALANCE_CLAIMS=off"

Any BALANCE_* switch of test/balance_test.dart can be set on either side
(several joined by spaces). Writes build/llm/balance_<time>.md.
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import llm  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SYSTEM = """你是阿瓦隆 AI 對手的平衡分析師。你會看到同一批模擬對局在兩種設定下的統計（A、B）。
欄位：正義勝率、各種邪惡獲勝方式、刺殺命中率、好人對乾淨／有壞人隊伍的贊成率等。
請用繁體中文：
1. 先列出 A 與 B 差異最大的幾個數字（附數值），並說明局數夠不夠下結論（樣本小的差異要保守）。
2. 推測造成差異的機制，標明是推測。
3. 建議下一組值得模擬比較的設定或要檢查的程式行為。
不要編造表格裡沒有的數字。"""


def run(games: int, seed: int, env_text: str, label: str, out_dir: Path) -> str:
    out = out_dir / f"balance_{label}.txt"
    env = dict(os.environ, BALANCE_GAMES=str(games), BALANCE_SEED=str(seed),
               BALANCE_OUT=str(out))
    for pair in env_text.split():
        key, _, value = pair.partition("=")
        env[key] = value
    print(f"  {label}: {env_text or '(預設)'} …", flush=True)
    subprocess.run(["flutter", "test", "test/balance_test.dart"], cwd=ROOT, env=env,
                   check=True, shell=os.name == "nt", stdout=subprocess.DEVNULL)
    return out.read_text(encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--games", type=int, default=300)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--a", default="", help='settings A, e.g. "BALANCE_LEVEL=normal"')
    parser.add_argument("--b", required=True, help='settings B, e.g. "BALANCE_CLAIMS=off"')
    parser.add_argument("--out", type=Path, default=ROOT / "build/llm")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    a = run(args.games, args.seed, args.a, "A", args.out)
    b = run(args.games, args.seed, args.b, "B", args.out)
    stamp = time.strftime("%Y%m%d_%H%M")
    path = args.out / f"balance_{stamp}.md"
    body = [f"# 平衡比較 {stamp}（各 {args.games} 局，種子 {args.seed}）", "",
            f"- A：{args.a or '(預設)'}", f"- B：{args.b}", "", "## A", "```", a.strip(), "```",
            "", "## B", "```", b.strip(), "```"]
    if llm.available():
        print("  reading the numbers …", flush=True)
        reading = llm.ask(SYSTEM, f"A（{args.a or '預設'}）：\n{a}\n\nB（{args.b}）：\n{b}",
                          temperature=0.2, context=16384)
        body += ["", f"## 模型的解讀（{llm.MODEL}，僅供參考）", "", reading.strip()]
    else:
        body += ["", f"（{llm.MODEL} 未就緒，只附數字）"]
    path.write_text("\n".join(body) + "\n", encoding="utf-8")
    print(f"report: {path}")


if __name__ == "__main__":
    main()
