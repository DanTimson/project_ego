"""
hooks.py — first-pass hook assignment for the Eador ability opcode corpus.

Produces a table mapping every ability_num opcode to a proposed hook point in
the turn / combat resolution sequence, with an explicit confidence mark.

METHOD AND ITS LIMITS. Assignment is by name pattern plus judgement about what
the ability plausibly does. It is NOT derived from observed behaviour and NOT
from the binary. Treat `high` as "the name leaves no room" (a flat stat delta),
`med` as "the family is clear, the exact firing point is not", and `low` as
"needs a play session or a breakpoint". The `low` and `med` rows are the
observation list.

Hook order below is the proposed resolution sequence. Getting this ORDER right
matters more than getting any single assignment right: order determines
rounding, clamping, and whether percentage modifiers compound.

Usage:
    python3 hooks.py <var-dir>              # markdown table to stdout
    python3 hooks.py <var-dir> --summary    # counts per hook
    python3 hooks.py <var-dir> --observe    # only the rows needing verification
"""

from __future__ import annotations

import re
import sys
import collections

import eador_var as E

# --------------------------------------------------------------------------
# The proposed hook taxonomy. Order is the resolution sequence.
# --------------------------------------------------------------------------

HOOKS = [
    # --- structural ---
    ("BATTLE_START",        "once per battle, before deployment resolves"),
    ("ROUND_START",         "top of each round, before initiative"),
    ("INITIATIVE",          "determines strike order within a round"),
    ("TURN_START",          "a unit's activation begins"),
    # --- movement ---
    ("MOVE_LEGALITY",       "may this unit move / onto this tile at all"),
    ("MOVE_COST",           "per-tile movement and stamina cost"),
    ("MOVE_COMPLETE",       "after a move resolves, before any attack"),
    # --- attack: attacker side ---
    ("ATTACK_DECLARE",      "target legality, number of attacks, range"),
    ("ATTACK_ACCURACY",     "chance to land, before damage is rolled"),
    ("DAMAGE_BASE",         "the attacker's raw damage figure"),
    ("DAMAGE_VS_TARGET",    "conditional multipliers keyed on target tags"),
    # --- attack: defender side ---
    ("EVASION",             "defender avoids the strike entirely"),
    ("DEFENCE_APPLY",       "defence/armour subtracted or bypassed"),
    ("DAMAGE_TAKEN",        "final modification of incoming damage"),
    ("ON_HIT",              "riders that fire when damage lands"),
    ("ON_DAMAGED",          "defender's reactive effects"),
    ("COUNTERATTACK",       "retaliation window"),
    ("ON_KILL",             "attacker-side effects on target death"),
    ("ON_DEATH",            "victim-side effects on own death"),
    # --- resources & state ---
    ("STAMINA",             "stamina drain, recovery, exemption"),
    ("MORALE",              "morale checks, fear, rage"),
    ("AMMO",                "ammunition capacity and replenishment"),
    ("REGEN",               "healing and regeneration ticks"),
    ("STATUS_APPLY",        "inflicting a status effect"),
    ("STATUS_RESIST",       "resisting or being immune to one"),
    # --- magic ---
    ("SPELL_POWER",         "caster-side spell magnitude and duration"),
    ("SPELL_GRANT",         "adds a castable spell to the unit"),
    ("SUMMON",              "summon strength, range, control"),
    # --- passive & aura ---
    ("STAT_PASSIVE",        "flat modifier to a derived stat"),
    ("AURA",                "affects other units by proximity or side"),
    # --- outside combat ---
    ("TURN_END",            "end of a unit's activation"),
    ("ROUND_END",           "end of round, before next initiative"),
    ("BATTLE_END",          "post-battle resolution, incl. field healing"),
    ("STRATEGIC",           "province/army layer, never fires in combat"),
    ("UNCLASSIFIED",        "no confident assignment"),
]

HOOK_ORDER = {name: i for i, (name, _) in enumerate(HOOKS)}

# --------------------------------------------------------------------------
# Classification rules, applied in order; first match wins.
# (regex, hook, confidence, note)
# --------------------------------------------------------------------------

RULES: list[tuple[str, str, str, str]] = [
    # --- unambiguous flat stat deltas -------------------------------------
    (r'^(Жизнь|Здоровье|Атака|Контратака|Защита|Защита от выстрела|Сопротивление|'
     r'Скорость|Дистанционная атака|Дальность выстрела|Запас снарядов|Выносливость|'
     r'Боевой дух|Сила|Сила воли|Броня)(\s*[+-]\d+)?$',
     "STAT_PASSIVE", "high", "flat delta to a named stat"),

    # --- spell grants ------------------------------------------------------
    (r'^Заклятье', "SPELL_GRANT", "high", "adds one spell; collapses to grant_spell(id)"),

    # --- immunities / resistances -----------------------------------------
    (r'^Иммунитет к', "STATUS_RESIST", "high", "categorical immunity to a status or school"),
    (r'^Уязвимость', "STATUS_RESIST", "med", "inverse immunity; check whether it multiplies or flags"),
    (r'^Устойчивость к', "STATUS_RESIST", "high", "partial resistance"),

    # --- movement ----------------------------------------------------------
    (r'^(Летающий|Низколетающий)$', "MOVE_COST", "high", "ignores or reduces terrain move cost"),
    (r'^(Не двигается|Обездвижен|Оплетён|Запутан)', "MOVE_LEGALITY", "high", "movement forbidden"),
    (r'^(Марш-бросок|Подвижность|Мобильный|Рывок)$', "MOVE_COST", "med",
     "extra movement — verify whether it adds range or reduces cost"),
    (r'^Атака с разгона', "MOVE_COMPLETE", "med",
     "charge: damage likely scales with tiles moved; verify the scaling"),
    (r'^(Стрельба на ходу|Подвижный стрелок|Удар и возврат)', "MOVE_COMPLETE", "med",
     "move-and-act; verify whether it re-enters ATTACK_DECLARE"),

    # --- strike order ------------------------------------------------------
    (r'^Первый удар', "INITIATIVE", "low",
     "first strike — reorders initiative or grants a pre-emptive attack? decisive difference"),
    (r'^(Стена копий|Держать строй|Удержание строя|Глухая оборона)', "COUNTERATTACK", "low",
     "formation reactions; firing condition and whether they stack are both unknown"),

    # --- accuracy / evasion ------------------------------------------------
    (r'^(Точный удар|Точный выстрел|Меткость|Снайперский выстрел|Эльфийская меткость)',
     "ATTACK_ACCURACY", "med", "accuracy — verify additive vs multiplicative"),
    (r'^(Уклонение|Парирование)', "EVASION", "low",
     "avoidance — verify whether it precedes the damage roll and whether it can chain"),

    # --- damage modification ----------------------------------------------
    (r'^(Бронебойный|Истончение брони|Разрушение брони|Повреждение брони)',
     "DEFENCE_APPLY", "low", "armour bypass — flat ignore, percentage, or defence debuff?"),
    (r'^(Охотник на|Сокрушение зла|Гроза |Убийца )', "DAMAGE_VS_TARGET", "med",
     "conditional bonus keyed on target tag"),
    (r'^(Магический удар|Магический выстрел|Магический бой)', "DAMAGE_BASE", "med",
     "damage typed as magical — likely bypasses physical defence"),
    (r'^(Не чувствует боли|Бестелесн|Каменная форма|Теневая форма|Газовая форма)',
     "DAMAGE_TAKEN", "med", "incoming damage reduction or nullification"),

    # --- on-hit riders -----------------------------------------------------
    (r'^(Оглушающий|Калечащий|Устрашающий|Ядовит|Обжигающая|Гниение|Кровотеч|Яд\b)',
     "ON_HIT", "med", "status rider on a landed hit"),
    (r'^(Похищение души|Похищение жизни|Кровопийца|Жизнеотбор|Всеобщий вампиризм)',
     "ON_HIT", "med", "lifesteal — verify it scales on damage dealt, not on damage rolled"),
    (r'^(Затаптывание|Круговая атака|Атака всех врагов|Двойной удар|Яростная атака|'
     r'Дополнительный выстрел|Двойной выстрел|Танец клинков)', "ATTACK_DECLARE", "med",
     "changes the number or shape of attacks"),
    (r'^(Шипы|Острые шипы|Ядовитая плоть|Чёрная кровь|Раскалённый)', "ON_DAMAGED", "med",
     "reflects onto the attacker"),

    # --- death -------------------------------------------------------------
    (r'^(Трупоед|Пожирание|Проглатывание|Переваривание)', "ON_KILL", "med",
     "consumes a corpse — verify timing against ON_DEATH effects"),
    (r'^(Реинкарнация|Тёмное возрождение|Феникс|Взрывное оружие|Суицид)', "ON_DEATH", "med",
     "fires on the unit's own death"),

    # --- resources ---------------------------------------------------------
    (r'^(Неутомимость|Восстановление сил|Медитация|Прилив сил)', "STAMINA", "med",
     "stamina economy"),
    (r'^(Неустрашимость|Устрашение|Страх|Аура страха|Боевое безумие|Безумная ярость|'
     r'Жажда крови|Бешенство|Кровавое безумие|Паника|Бесстрашие)', "MORALE", "low",
     "morale system — the check formula and its trigger points are entirely unknown"),
    (r'^(Сбор снарядов|Кража снарядов|Восстановить снаряды|Восстановление снарядов|'
     r'Тяжёлые снаряды|Смена снарядов|Острые стрелы|Пылающие стрелы|Зачарованные стрелы)',
     "AMMO", "med", "ammunition"),
    (r'^(Регенерация|Целительство|Первая помощь|Излечение|Исцеление|Живучесть)',
     "REGEN", "low",
     "healing — in-combat tick vs post-battle recovery differ; Первая помощь is likely BATTLE_END"),

    # --- magic -------------------------------------------------------------
    (r'^(Сила заклинаний|Длительность заклинаний|Контроль энергий|Тавматургия|Сила воли)',
     "SPELL_POWER", "med", "caster attribute"),
    (r'^(Сила призыва|Дальность призыва|Призыв|Призвать|Вызов|Подъятие|Создание)',
     "SUMMON", "med", "summoning"),
    (r'^(Снятие чар|Разрушение заклинаний|Антимагия|Щит магии|Волшебный щит)',
     "STATUS_RESIST", "med", "dispel or ward"),

    # --- auras -------------------------------------------------------------
    (r'^(Аура|Командор|Лидер|Вождь|Присутствие|Гнетущее|Давящее|Вдохновляющее|'
     r'Слово |Клич |Гимн |Вой|Жуткий вой|Инфернальный вой|Демонический вой)',
     "AURA", "low", "area effect — radius, side, and stacking all unverified"),

    # --- strategic layer ---------------------------------------------------
    (r'^(Мародёр|Грабитель|Фуражир|Трудоголик|Ремонт|Снабженец|Оруженосец|Содержание|'
     r'Ищейка|Землепроходец|Знание |Голод|Сильный голод|Терпимость)', "STRATEGIC", "med",
     "province/army layer — should never be reachable from the combat pipeline"),
    (r'^Стать ', "STRATEGIC", "high", "unit promotion; an option-layer concern, not a combat hook"),

    # ----------------------------------------------------------------------
    # second pass: families the first pass missed
    # ----------------------------------------------------------------------
    (r'^(Не сражается|Не колдует|Не перемещается)', "MOVE_LEGALITY", "high",
     "categorical action prohibition — belongs in legality, not as a stat"),
    (r'^(Доход золота|Доход кристаллов|Искусный дипломат|Смена типа)', "STRATEGIC", "med",
     "province layer; 'Смена типа' has 17 uses — confirm it is a tag mutation, not combat"),
    (r'^Насылает ', "ON_HIT", "med", "inflicts a disease status on hit"),
    (r'(выстрел|снаряд|Бомбардировка|Сейсмозаряд|Стреломёт)', "ATTACK_DECLARE", "med",
     "ranged attack variant — verify whether it replaces or supplements the normal shot"),
    (r'^Осада', "DAMAGE_VS_TARGET", "med", "siege bonus, presumably vs fortification tags"),
    (r'^(Окаменение|Паутина|Корни|Сглаз|Ловчая сеть|Проклятие|Ослабление|Сдерживание)',
     "ON_HIT", "med", "control status applied on hit or on cast"),
    (r'^(Повреждение оружия|Повреждение ауры|Гниющие раны)', "ON_HIT", "med",
     "degrades a target resource rather than dealing damage"),
    (r'^(Удар щитом|Удар в спину|Сокрушающий удар|Общая атака|Пылающий клинок|'
     r'Острое оружие|Зачарованный клинок|Смертельное касание|Леденящее касание)',
     "DAMAGE_BASE", "med", "special strike — verify it modifies damage rather than adding an attack"),
    (r'^(Ловкость|Бдительность|Настороженность)', "EVASION", "low",
     "defensive reaction — could equally be ATTACK_ACCURACY; needs observation"),
    (r'^(Тяжёлая броня|Облегчённая броня|Броня веры|Проклятая броня|Небесная броня|'
     r'Рунная броня)', "DAMAGE_TAKEN", "med", "armour variant"),
    (r'^(Тёмное превосходство|Мощь гноллов|Безумие орков|Гнев болот|Стойкость племени|'
     r'Ярость альваров|Ярость предков|Мощь )', "DAMAGE_VS_TARGET", "low",
     "faction/terrain conditional — the predicate is not recoverable from the name"),
    (r'^(Повелитель нежити|Контроль нежити|Контроль разума|Подчинение|Подчинить|'
     r'Вечное рабство|Приказ)', "SUMMON", "low",
     "control effects — verify whether they route through the summon system or a separate one"),
    (r'^(Преодоление сопротивления|Умелый заклинатель|Эксперт заклинания|'
     r'Мастерство чародея|Мастерство призыва)', "SPELL_POWER", "med", "caster attribute"),
    (r'^(Восполнение снарядов|Тёмное восполнение)', "AMMO", "med", "resource replenishment"),
    (r'^(Опытный лекарь|Живительная сила)', "REGEN", "med", "healing attribute"),
    (r'^(Самоконтроль|Стойкий разум|Иммунитет|Пойманная душа)', "STATUS_RESIST", "med",
     "mental resistance"),
    (r'^(Осадный режим|Каменная форма|Меняющий Облик|Смена оружия|Сменить )',
     "TURN_START", "low", "stance toggle — an action, not a passive; verify the action economy"),
]


def classify(name: str):
    for pattern, hook, conf, note in RULES:
        if re.match(pattern, name or ""):
            return hook, conf, note
    return "UNCLASSIFIED", "low", "no rule matched — assign by hand"


def build(directory: str):
    ab = E.parse(f"{directory}/ability_num.var")
    up = E.parse(f"{directory}/unit_upg.var")

    # usage: how many unit_upg options reference each opcode
    usage = collections.Counter()
    for r in up.records:
        t = r.get("Upg Type")
        if isinstance(t, int):
            usage[t] += 1

    rows = []
    for r in ab.records:
        n = r.get("Number")
        if not isinstance(n, int):
            continue
        name = r.get("Name") or ""
        if name == "Пусто":
            continue
        hook, conf, note = classify(name)
        rows.append({
            "opcode": n,
            "name": name,
            "hook": hook,
            "conf": conf,
            "note": note,
            "uses": usage.get(n, 0),
            "numeric": r.get("Numeric"),
            "percent": r.get("Percent"),
        })
    rows.sort(key=lambda x: (HOOK_ORDER[x["hook"]], -x["uses"], x["opcode"]))
    return rows


def markdown(rows):
    out = ["# Proposed hook assignment", ""]
    out.append(f"{len(rows)} opcodes. `uses` = number of unit_upg options referencing this opcode.")
    out.append("")
    for hook, desc in HOOKS:
        group = [r for r in rows if r["hook"] == hook]
        if not group:
            continue
        out.append(f"## {hook}")
        out.append(f"*{desc}* — {len(group)} opcodes")
        out.append("")
        out.append("| opcode | name | conf | uses | note |")
        out.append("|---|---|---|---|---|")
        for r in group:
            out.append(f"| {r['opcode']} | {r['name']} | {r['conf']} | {r['uses']} | {r['note']} |")
        out.append("")
    return "\n".join(out)


def summary(rows):
    by_hook = collections.Counter(r["hook"] for r in rows)
    by_conf = collections.Counter(r["conf"] for r in rows)
    print(f"{'hook':20}{'opcodes':>9}{'options':>9}")
    for hook, _ in HOOKS:
        if not by_hook[hook]:
            continue
        opts = sum(r["uses"] for r in rows if r["hook"] == hook)
        print(f"{hook:20}{by_hook[hook]:>9}{opts:>9}")
    print(f"\nconfidence: {dict(by_conf)}")
    need = [r for r in rows if r["conf"] in ("low",) or r["hook"] == "UNCLASSIFIED"]
    print(f"rows needing verification before implementation: {len(need)}")


if __name__ == "__main__":
    d = sys.argv[1] if len(sys.argv) > 1 else "var"
    rows = build(d)
    if "--summary" in sys.argv:
        summary(rows)
    elif "--observe" in sys.argv:
        need = [r for r in rows if r["conf"] == "low" or r["hook"] == "UNCLASSIFIED"]
        need.sort(key=lambda x: -x["uses"])
        print(f"{'opcode':>7}  {'uses':>5}  {'hook':18} name")
        for r in need:
            print(f"{r['opcode']:>7}  {r['uses']:>5}  {r['hook']:18} {r['name']}")
    else:
        print(markdown(rows))
