extends SceneTree

const Authored = preload("res://content/campaign/native_campaign.gd")
var failures := 0


func check(condition: bool, message: String) -> void:
	print("%s  %s" % ["PASS" if condition else "FAIL", message])
	if not condition:
		failures += 1


func refuse(model: StrategicCampaign, action: Callable, message: String) -> void:
	var before := model.snapshot()
	check(not action.call().ok and model.snapshot() == before, message)


func unit_id(encounter: CampaignEncounter, roster_id: String) -> String:
	return encounter._mapping[roster_id].instance_id


func win(model: StrategicCampaign, destination: String, sacrifice := false) -> CampaignEncounter:
	var opened := model.travel(destination)
	check(opened.ok and opened.has("encounter"), "open " + destination)
	if not opened.ok or not opened.has("encounter"):
		return null
	var encounter: CampaignEncounter = opened.encounter
	check(encounter.session.begin().ok, "begin " + destination)
	if sacrifice:
		check(
			(
				encounter
				. session
				. issue_command(
					{
						"op": "attack",
						"unit": unit_id(encounter, "azure-scout"),
						"target": encounter.session.living_units(1)[0].instance_id
					}
				)
				. accepted
			),
			"Scout attacks through real tactical command"
		)
	check(
		(
			encounter
			. session
			. issue_command(
				{
					"op": "attack",
					"unit": unit_id(encounter, "azure-vanguard"),
					"target": encounter.session.living_units(1)[0].instance_id
				}
			)
			. accepted
		),
		"Vanguard attacks through real tactical command"
	)
	check(encounter.session.winning_side_id() == 0, "real Azure victory at " + destination)
	var result := model.finish(encounter)
	check(result.ok, "collect and apply " + destination + ": " + str(result))
	return encounter


func test_routes() -> void:
	for route in [["ford", "watchpost", "keep"], ["quarry", "mill", "keep"]]:
		var model := StrategicCampaign.create(Authored.definition())
		var income := 3
		var gold := 12
		var turn := 0
		for destination in route:
			var encounter := win(model, destination)
			income += model.content().provinces[destination].income
			gold += income
			turn += 1
			var state := model.snapshot()
			print(
				(
					"ROUTE %s: turn=%d gold=%d life=%d"
					% [
						destination,
						state.turn,
						state.gold,
						state.roster.entries["azure-vanguard"].life
					]
				)
			)
			check(
				(
					state.turn == turn
					and state.gold == gold
					and state.position == destination
					and destination in state.owned
				),
				"exact capture, turn and income accounting"
			)
			refuse(
				model,
				func() -> Dictionary: return model.finish(encounter),
				"duplicate result unchanged"
			)
		check(model.snapshot().status == "victory", "either route wins without paid services")
		refuse(model, func() -> Dictionary: return model.travel("home"), "terminal travel refused")
		refuse(model, model.recruit, "terminal recruitment refused")
		refuse(model, model.recover, "terminal recovery refused")
		check(
			StrategicCampaign.from_checkpoint(Authored.definition(), model.checkpoint().data).ok,
			"terminal victory checkpoint remains inspectable"
		)


func test_guards_and_services() -> void:
	var model := StrategicCampaign.create(Authored.definition())
	refuse(model, func() -> Dictionary: return model.travel("keep"), "nonadjacent travel unchanged")
	refuse(
		model, func() -> Dictionary: return model.travel("missing"), "unknown destination unchanged"
	)
	refuse(
		model, func() -> Dictionary: return model.travel("home"), "same-position travel unchanged"
	)
	refuse(model, model.recover, "full-life recovery cannot charge")
	var first := win(model, "ford", true)
	var state := model.snapshot()
	print("FIRST SERVICE CAPTURE: life=", state.roster.entries["azure-vanguard"].life)
	check(
		(
			state.roster.entries["azure-scout"].life == 0
			and state.roster.entries["azure-vanguard"].life < 20
		),
		"wounded survivor and persistent casualty"
	)
	refuse(model, model.recover, "Home-only recovery")
	refuse(model, model.recruit, "Home-only recruitment")
	check(
		model.travel("home").ok and model.snapshot().gold == 26 and model.snapshot().turn == 2,
		"friendly return pays owned income once"
	)
	var wounded: int = model.snapshot().roster.entries["azure-vanguard"].life
	check(
		model.recover().ok and model.snapshot().gold == 25 and model.snapshot().turn == 3,
		"recovery spends 8 before income 7"
	)
	check(
		(
			model.snapshot().roster.entries["azure-vanguard"].life == mini(20, wounded + 6)
			and model.snapshot().roster.entries["azure-scout"].life == 0
		),
		"heal survivors only to maximum"
	)
	check(
		model.recruit().ok and model.snapshot().gold == 22 and model.snapshot().turn == 4,
		"recruit spends 10 before income 7"
	)
	check(model.travel("ford").ok, "backtrack through friendly Ford")
	var second := win(model, "watchpost")
	check(
		(
			not second._mapping.has("azure-scout")
			and second._mapping.has("recruit-1")
			and (
				second.session.scenario.units[unit_id(second, "azure-vanguard")]
				!= first.session.scenario.units[unit_id(first, "azure-vanguard")]
			)
		),
		"casualty excluded, recruit deployed and tactical objects fresh"
	)
	win(model, "keep")
	check(model.snapshot().status == "victory", "service route wins")
	print(
		"SERVICE ROUTE: turn=7 gold=61 life=",
		model.snapshot().roster.entries["azure-vanguard"].life
	)
	var cap := StrategicCampaign.create(Authored.definition())
	check(cap.recruit().ok, "first opening recruit affordable")
	refuse(cap, cap.recruit, "pre-action gold 5 cannot borrow post-action income")
	win(cap, "quarry")
	check(cap.travel("home").ok and cap.recruit().ok, "second recruit after earning income")
	check(
		(
			cap.snapshot().roster.entries.has("recruit-1")
			and cap.snapshot().roster.entries.has("recruit-2")
		),
		"unique persistent recruitment IDs"
	)
	refuse(cap, cap.recruit, "four living members cap")
	var full: CampaignEncounter = cap.travel("ford").encounter
	check(
		full._mapping.size() == 4 and full.session.scenario.state.side(0).living().size() == 4,
		"four living units have distinct legal authored deployment positions"
	)
	var poor := StrategicCampaign.create(Authored.definition())
	var data: Dictionary = poor.checkpoint().data
	data.state.gold = 0
	poor = StrategicCampaign.from_checkpoint(Authored.definition(), data).campaign
	refuse(poor, poor.recruit, "unaffordable recruit unchanged")
	win(poor, "ford")
	poor.travel("home")
	data = poor.checkpoint().data
	data.state.gold = 7
	poor = StrategicCampaign.from_checkpoint(Authored.definition(), data).campaign
	refuse(poor, poor.recover, "unaffordable recovery unchanged")


func test_battle_refusals() -> void:
	var model := StrategicCampaign.create(Authored.definition())
	var encounter: CampaignEncounter = model.travel("ford").encounter
	refuse(model, func() -> Dictionary: return model.travel("quarry"), "in-flight travel unchanged")
	refuse(model, model.recruit, "in-flight service unchanged")
	refuse(
		model, func() -> Dictionary: return model.finish(encounter), "unstarted result unchanged"
	)
	check(not model.checkpoint().ok, "no mid-battle checkpoint")
	encounter.session.begin()
	refuse(
		model, func() -> Dictionary: return model.finish(encounter), "unfinished result unchanged"
	)
	encounter.session.scenario.runtime_error = "test fatal halt"
	refuse(model, func() -> Dictionary: return model.finish(encounter), "halted result unchanged")
	check(
		(
			model.abandon(encounter).ok
			and model.snapshot().turn == 0
			and model.snapshot().gold == 12
			and model.snapshot().owned == ["home"]
		),
		"halted abandonment has no turn, income or capture"
	)
	refuse(
		model, func() -> Dictionary: return model.finish(encounter), "abandoned result unchanged"
	)
	var retried: CampaignEncounter = model.travel("ford").encounter
	check(
		(
			retried.session.living_units(1)[0].instance_id
			!= encounter.session.living_units(1)[0].instance_id
		),
		"enemy retry identities also fresh"
	)
	check(
		(
			unit_id(retried, "azure-vanguard") != unit_id(encounter, "azure-vanguard")
			and retried.session.scenario.units[unit_id(retried, "azure-vanguard")].life == 20
		),
		"retry uses fresh identities and unchanged roster life"
	)
	retried.session.begin()
	retried.session.issue_command(
		{
			"op": "attack",
			"unit": unit_id(retried, "azure-vanguard"),
			"target": retried.session.living_units(1)[0].instance_id
		}
	)
	var unit: Combatant = retried.session.scenario.units[unit_id(retried, "azure-vanguard")]
	unit.instance_id = "tampered"
	refuse(
		model,
		func() -> Dictionary: return model.finish(retried),
		"invalid tactical identity unchanged"
	)


func test_terminal_edges() -> void:
	var content := Authored.definition()
	content.turn_limit = 3
	var model := StrategicCampaign.create(content)
	for destination in ["quarry", "mill", "keep"]:
		win(model, destination)
	check(
		model.snapshot().turn == 3 and model.snapshot().status == "victory",
		"final available turn captures Keep before exhaustion"
	)
	content.turn_limit = 1
	model = StrategicCampaign.create(content)
	win(model, "ford")
	check(
		model.snapshot().status == "defeat" and model.snapshot().gold == 19,
		"turn exhaustion after capture and income"
	)
	check(
		StrategicCampaign.from_checkpoint(content, model.checkpoint().data).ok,
		"turn-exhausted terminal checkpoint accepted"
	)
	model = StrategicCampaign.create(Authored.definition())
	var encounter: CampaignEncounter = model.travel("ford").encounter
	encounter.session.begin()
	# Real commands let Crimson defeat both units; no victory toggle.
	for index in 30:
		if encounter.session.battle_complete():
			break
		if encounter.session.active_side_id() == 1:
			CrimsonPolicy.run_phase(encounter.session)
		else:
			encounter.session.issue_command({"op": "end_phase"})
	check(
		encounter.session.winning_side_id() == 1 and model.finish(encounter).ok,
		"real Crimson victory commits defeat"
	)
	check(
		(
			model.snapshot().status == "defeat"
			and model.snapshot().turn == 1
			and model.snapshot().gold == 15
			and model.snapshot().owned == ["home"]
		),
		"defeat turn pays only preexisting ownership income"
	)
	# Draw collection is already supported by the bridge; exercise the strategic branch.
	model = StrategicCampaign.create(Authored.definition())
	encounter = model.travel("ford").encounter
	encounter.session.begin()
	for member in encounter.session.scenario.units.values():
		member.life = 0
		member.alive = false
	check(
		(
			encounter.session.winning_side_id() == -1
			and model.finish(encounter).ok
			and model.snapshot().status == "defeat"
		),
		"draw ends campaign in defeat"
	)


func _initialize() -> void:
	test_routes()
	test_guards_and_services()
	test_battle_refusals()
	test_terminal_edges()
	print("STRATEGIC MODEL: %d failures" % failures)
	quit(0 if failures == 0 else 1)
