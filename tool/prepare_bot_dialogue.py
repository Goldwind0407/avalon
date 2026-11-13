"""Compile the reviewed draft into a strict, deterministic runtime catalog.

The draft remains editable documentation. This importer fixes only explicit
schema aliases/wording reviewed in docs/solo_bot_v2_review.md. Chinese trigger
descriptions are metadata, never executable expressions.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/avalon_bot_dialogue_templates_v2.json"
DEST = ROOT / "lib/features/solo/dialogue/generated/bot_dialogue_data.dart"
WORDING = ROOT / "docs/bot_dialogue_natural.txt"
ROLES = dict(zip(
    ["all", "loyal_servant", "merlin", "percival", "evil_minion", "assassin",
     "morgana", "mordred", "oberon", "lancelot_good", "lancelot_evil"],
    ["all", "loyal", "merlin", "percival", "minion", "assassin",
     "morgana", "mordred", "oberon", "lancelotGood", "lancelotEvil"]))
POLICIES = {
    "public_grounded": "publicGrounded",
    "private_truth_claim": "privateTruthClaim",
    "private_strategy_public_claim": "privateStrategyPublicClaim",
    "strategic_opinion_bluff": "strategicOpinionBluff",
    # Explicit, reviewed alias; unknown policies still fail the build.
    "intentional_opinion_bluff": "strategicOpinionBluff",
    "explicit_private_claim_lie": "explicitPrivateClaimLie",
}
GROUPS = {
    "G": "hedge supportTeam supportTeam opposeTeam opposeTeam warnFifthVote warnFifthVote explainTeam explainTeam questionTeam defendSelf defendSelf defendSelf quoteQuest quoteQuest challengeVote replyQuestion defendOther reassess avoidRepeat hedge endgame explainVote questionTeam",
    "RLS": "hedge quoteQuest reassess challengeClaim explainTeam challengeClaim",
    "RME": "opposeTeam opposeTeam supportTeam accuse replyQuestion reassess endgame",
    "RPC": "hedge defendOther hedge challengeClaim misdirect defendOther challengeClaim",
    "REV": "bluff defendOther misdirect accuse misdirect endgame",
    "RAS": "challengeClaim challengeClaim questionTeam challengeClaim misdirect assassinate hedge",
    "RMG": "hedge challengeClaim replyQuestion misdirect defendSelf accuse challengeClaim",
    "RMD": "hedge supportTeam hedge defendSelf misdirect endgame",
    "ROB": "hedge hedge defendSelf hedge accuse interpretLady opposeTeam",
    "RLG": "discussLancelot discussLancelot supportTeam discussLancelot defendSelf endgame",
    "RLE": "discussLancelot hedge replyQuestion hedge discussLancelot defendSelf misdirect",
    "XLD": "interpretLady interpretLady interpretLady challengeLady challengeLady",
    "XSW": "discussSword discussSword discussSword discussSword",
    "XLC": "discussLancelot discussLancelot",
    "XQT": "quoteQuest quoteQuest",
    "XVR": "challengeClaim challengeClaim",
}
PLACEHOLDERS = {"目標": "target", "失敗張數": "fails", "其他隊員": "otherMembers",
                "沿用隊員": "reusedMembers", "宣稱者": "claimant", "宣稱陣營": "claimedAlignment",
                "新隊員": "newMember", "舊隊員": "oldMember", "辯護者": "defender"}


def compile_catalog():
    import re
    source = json.loads(SOURCE.read_text(encoding="utf-8-sig"))
    rules, seen = [], set()
    for entry in source["entries"]:
        rule_id = entry["id"]
        if rule_id in seen:
            raise ValueError(f"Duplicate rule: {rule_id}")
        seen.add(rule_id)
        match = re.fullmatch(r"([A-Z]+)(\d+)", rule_id)
        prefix, index = match.group(1), int(match.group(2)) - 1
        intent = GROUPS[prefix].split()[index]
        templates = []
        for text in entry["templates"]:
            # A seat label already contains its number, 號, and nickname.
            for name, key in PLACEHOLDERS.items():
                text = text.replace(f"【{name}】號", "{{" + key + "}}")
                text = text.replace(f"【{name}】", "{{" + key + "}}")
            text = text.replace("【輪次】", "{{attempt}}" if "提案" in text else "{{quest}}")
            if "【" in text or "】" in text:
                raise ValueError(f"Unknown placeholder: {rule_id}: {text}")
            if rule_id == "XSW03":
                text = text.replace("翻牌改變了最後結果", "翻牌增加了一張失敗牌")
            if rule_id == "XSW04":
                text = text.replace("只有使用劍的人知道原始牌", "出牌者知道自己的牌，持劍者能看到被翻轉的那張")
            if rule_id == "G16":
                text = "比較兩次已公開的投票：" + text.replace("上次", "前一次").replace("這次", "後一次")
            if rule_id == "RME02":
                # The registered evidence is quest participation/fail count,
                # not the target's vote or leadership of a past proposal.
                text = ("我對{{target}}有疑慮，依據是第{{quest}}次遠征出現的失敗牌。"
                        if len(templates) == 0 else
                        "我想檢查{{target}}參與第{{quest}}次遠征的紀錄，但這還不能單獨證明他的陣營。")
            if rule_id == "RME04" and len(templates) == 1:
                text = "我同意先檢查{{target}}參與第{{quest}}次遠征的紀錄，但先不要把話說死。"
            if rule_id == "RLS04":
                text = text.replace("在第一場就", "")
            if rule_id == "G21" and len(templates) == 0:
                text = "我目前只能給初步判斷，還不到能保證他好壞的程度。"
            if rule_id == "RPC07" and len(templates) == 0:
                text = "這兩份公開說法不一致，先把對應的遠征整理清楚。"
            if rule_id == "RAS01" and len(templates) == 1:
                text = "我想了解你目前的判斷，是依據哪一段公開紀錄？"
            if rule_id == "REV04":
                text = text.replace("解釋上一票", "解釋對應的公開紀錄")
            if rule_id == "RMG06" and len(templates) == 1:
                text = "現在我傾向先檢查{{target}}，因為他參與的第{{quest}}次遠征有失敗牌。"
            if rule_id == "ROB05":
                text = "{{target}}參與的第{{quest}}次遠征有失敗牌，我想先聽他的解釋。"
            if rule_id == "ROB06":
                text = ("女神的宣稱我們先記下，也要分清楚查驗的時間。" if len(templates) == 0 else
                        "這個查驗宣稱值得參考，我想先確認它適用的是哪次遠征結束時的狀態。")
            if rule_id == "RLE07" and len(templates) == 0:
                text = "轉換資訊先記下，我更想看這隊具體怎麼選人。"
            templates.append(text)
        rules.append({"id": rule_id, "role": ROLES[entry["role"]],
                      "phase": entry["phase"], "intent": intent,
                      "scenario": entry["intent"], "priority": entry["priority"],
                      "policy": POLICIES[entry["claim_policy"]],
                      "requires": entry["prerequisites"],
                      "sourceTrigger": entry["trigger"], "templates": templates})
    wording = {}
    for line in WORDING.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        rule_id, *lines = [part.strip() for part in line.split("|")]
        if rule_id in wording or len(lines) != 4 or len(set(lines)) != 4:
            raise ValueError(f"Expected four unique variants: {rule_id}")
        for text in lines:
            keys = re.findall(r"\{\{([A-Za-z]+)\}\}", text)
            if set(keys) - set(PLACEHOLDERS.values()) - {"quest", "attempt"}:
                raise ValueError(f"Unknown wording placeholder: {rule_id}")
            if re.search(r"[{}]", re.sub(r"\{\{[A-Za-z]+\}\}", "", text)):
                raise ValueError(f"Malformed wording placeholder: {rule_id}")
        wording[rule_id] = lines
    if set(wording) != seen:
        raise ValueError(f"Wording IDs differ: {set(wording) ^ seen}")
    for rule in rules:
        rule["templates"] = wording[rule["id"]]
    return {"schemaVersion": 1, "sourceVersion": source["version"], "rules": rules}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    catalog = compile_catalog()
    payload = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
    if "'''" in payload:
        raise ValueError("Dialogue text cannot terminate the generated raw string")
    result = "// GENERATED by tool/prepare_bot_dialogue.py. Do not edit.\n// dart format off\n" + \
        "const String botDialogueData = r'''\n" + payload + "''';\n"
    if args.check:
        if not DEST.exists() or DEST.read_text(encoding="utf-8") != result:
            raise SystemExit("Dialogue catalog is stale. Run python tool/prepare_bot_dialogue.py")
    else:
        DEST.parent.mkdir(parents=True, exist_ok=True)
        DEST.write_text(result, encoding="utf-8", newline="\n")
    print(f"Validated {len(catalog['rules'])} rules / "
          f"{sum(len(r['templates']) for r in catalog['rules'])} templates")


if __name__ == "__main__":
    main()
