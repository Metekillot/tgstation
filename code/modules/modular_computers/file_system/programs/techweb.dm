/datum/computer_file/program/science
	filename = "experi_track"
	filedesc = "Nanotrasen Science Hub"
	downloader_category = PROGRAM_CATEGORY_SCIENCE
	program_open_overlay = "research"
	extended_desc = "Connect to the internal science server in order to assist in station research efforts."
	program_flags = PROGRAM_ON_NTNET_STORE | PROGRAM_REQUIRES_NTNET
	size = 10
	tgui_id = "NtosTechweb"
	program_icon = "atom"
	run_access = list(ACCESS_COMMAND, ACCESS_RESEARCH)
	download_access = list(ACCESS_RESEARCH)
	/// Reference to global science techweb
	var/datum/techweb/stored_research
	/// Access needed to lock/unlock the console
	var/lock_access = ACCESS_RESEARCH
	/// Used for compressing data sent to the UI via static_data as payload size is of concern
	var/id_cache = list()
	/// Sequence var for the id cache
	var/id_cache_seq = 1

/datum/computer_file/program/science/Destroy()
	..()
	UnregisterSignal(computer, COMSIG_MODULAR_COMPUTER_INSERTED_ID)

/datum/computer_file/program/science/on_install(datum/computer_file/source, obj/item/modular_computer/computer_installing)
	. = ..()
	if(!CONFIG_GET(flag/no_default_techweb_link) && !stored_research)
		CONNECT_TO_RND_SERVER_ROUNDSTART(stored_research, computer)
	RegisterSignal(computer, COMSIG_MODULAR_COMPUTER_INSERTED_ID, PROC_REF(notify_techweb))

/datum/computer_file/program/science/proc/notify_techweb(datum/source, obj/item/card/inserting_id, mob/user)
	SIGNAL_HANDLER

	if(!stored_research) // we can't notify a techweb we don't have
		return
	if(stored_research.consoles_accessing[computer] && stored_research.users_accessing[inserting_id]) // we already have a record of both this terminal and that user
		return
	if(can_run(user))
		SEND_SIGNAL(stored_research, COMSIG_TECHWEB_NEW_CONNECTION, src, inserting_id, user)


/datum/computer_file/program/science/can_run(mob/living/user) // we check off of IDs deliberately; silicons can always access the research web
	. = ..()
	if(!.)
		return FALSE
	var/accessing_id = computer?.computer_id_slot
	if(stored_research && stored_research.users_accessing[accessing_id])
		var/user_record = stored_research.users_accessing[accessing_id]
		if(user_record["locked"] == TRUE)
			return FALSE
	return TRUE

/datum/computer_file/program/science/application_attackby(obj/item/attacking_item, mob/living/user)
	if(!istype(attacking_item, /obj/item/multitool))
		return FALSE
	var/obj/item/multitool/attacking_tool = attacking_item
	if(!QDELETED(attacking_tool.buffer) && istype(attacking_tool.buffer, /datum/techweb))
		stored_research = attacking_tool.buffer
	return TRUE

/datum/computer_file/program/science/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet/research_designs)
	)

// heavy data from this proc should be moved to static data when possible
/datum/computer_file/program/science/ui_data(mob/user)
	var/list/data = list()
	data["stored_research"] = !!stored_research
	if(!stored_research) //lack of a research node is all we care about.
		return data
	data += list(
		"nodes" = list(),
		"experiments" = list(),
		"researched_designs" = stored_research.researched_designs,
		"points" = stored_research.research_points,
		"points_last_tick" = stored_research.last_bitcoins,
		"web_org" = stored_research.organization,
		"sec_protocols" = !(computer.obj_flags & EMAGGED),
		"t_disk" = null, //Not doing disk operations on the app, use the console for that.
		"d_disk" = null, //See above.
		"locked" = stored_research.consoles_accessing[computer]["locked"],
	)

	// Serialize all nodes to display
	for(var/tier in stored_research.tiers)
		var/datum/techweb_node/node = SSresearch.techweb_node_by_id(tier)

		// Ensure node is supposed to be visible
		if (stored_research.hidden_nodes[tier])
			continue

		data["nodes"] += list(list(
			"id" = node.id,
			"can_unlock" = stored_research.can_unlock_node(node),
			"tier" = stored_research.tiers[node.id]
		))

	// Get experiments and serialize them
	var/list/exp_to_process = stored_research.available_experiments.Copy()
	for (var/comp_experi in stored_research.completed_experiments)
		exp_to_process += stored_research.completed_experiments[comp_experi]
	for (var/process_experi in exp_to_process)
		var/datum/experiment/unf_experi = process_experi
		data["experiments"][unf_experi.type] = list(
			"name" = unf_experi.name,
			"description" = unf_experi.description,
			"tag" = unf_experi.exp_tag,
			"progress" = unf_experi.check_progress(),
			"completed" = unf_experi.completed,
			"performance_hint" = unf_experi.performance_hint
		)
	return data

/datum/computer_file/program/science/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	var/locked = FALSE // barring someone locking us out, we're not locked
	var/card_access = computer?.computer_id_slot?.access
	if(!card_access)
		card_access = null // just to be sure we don't end up in some undefined circumstance
	var/user_data = card_access ? stored_research.users_accessing[computer?.computer_id_slot] : null
	var/console_data = stored_research.consoles_accessing[computer]
	if(computer.obj_flags & EMAGGED) // emagged doesn't give a shit about being locked by the server controller
		locked = FALSE
	else
		if((user_data && user_data["locked"] == TRUE) || console_data["locked"] == TRUE) // make sure we have user data in case a silicon uses this program on a modular computer
			locked = TRUE
	// Check if the console is locked to block any actions occuring
	if (locked && action != "toggleLock")
		computer.say("Console is locked, cannot perform further actions.")
		return TRUE

	switch (action)
		if ("toggleLock")
			if(computer.obj_flags & EMAGGED)
				to_chat(usr, span_boldwarning("Security protocol error: Unable to access locking protocols."))
				return TRUE
			if((lock_access in card_access)  || HAS_SILICON_ACCESS(usr)) // 'in' operator on a null always returns false
				SEND_SIGNAL(stored_research, COMSIG_RESEARCH_CONSOLE_TOGGLE_LOCK, src, list(card_access))
			else
				to_chat(usr, span_boldwarning("Unauthorized Access. Please insert ID card: [lock_access]."))
			return TRUE
		if ("researchNode")
			research_node(params["node_id"], usr)
			return TRUE

/datum/computer_file/program/science/ui_static_data(mob/user)
	. = list(
		"static_data" = list(),
		"point_types_abbreviations" = SSresearch.point_types,
	)

	// Build node cache...
	// Note this looks a bit ugly but its to reduce the size of the JSON payload
	// by the greatest amount that we can, as larger JSON payloads result in
	// hanging when the user opens the UI
	var/node_cache = list()
	for (var/node_id in SSresearch.techweb_nodes)
		var/datum/techweb_node/node = SSresearch.techweb_nodes[node_id] || SSresearch.error_node
		var/compressed_id = "[compress_id(node.id)]"
		node_cache[compressed_id] = list(
			"name" = node.display_name,
			"description" = node.description
		)
		if (LAZYLEN(node.research_costs))
			node_cache[compressed_id]["costs"] = list()
			for (var/node_cost in node.research_costs)
				node_cache[compressed_id]["costs"]["[compress_id(node_cost)]"] = node.research_costs[node_cost]
		if (LAZYLEN(node.prereq_ids))
			node_cache[compressed_id]["prereq_ids"] = list()
			for (var/prerequisite_node in node.prereq_ids)
				node_cache[compressed_id]["prereq_ids"] += compress_id(prerequisite_node)
		if (LAZYLEN(node.design_ids))
			node_cache[compressed_id]["design_ids"] = list()
			for (var/unlocked_design in node.design_ids)
				node_cache[compressed_id]["design_ids"] += compress_id(unlocked_design)
		if (LAZYLEN(node.unlock_ids))
			node_cache[compressed_id]["unlock_ids"] = list()
			for (var/unlocked_node in node.unlock_ids)
				node_cache[compressed_id]["unlock_ids"] += compress_id(unlocked_node)
		if (LAZYLEN(node.required_experiments))
			node_cache[compressed_id]["required_experiments"] = node.required_experiments
		if (LAZYLEN(node.discount_experiments))
			node_cache[compressed_id]["discount_experiments"] = node.discount_experiments

	// Build design cache
	var/design_cache = list()
	var/datum/asset/spritesheet/research_designs/spritesheet = get_asset_datum(/datum/asset/spritesheet/research_designs)
	var/size32x32 = "[spritesheet.name]32x32"
	for (var/design_id in SSresearch.techweb_designs)
		var/datum/design/design = SSresearch.techweb_designs[design_id] || SSresearch.error_design
		var/compressed_id = "[compress_id(design.id)]"
		var/size = spritesheet.icon_size_id(design.id)
		design_cache[compressed_id] = list(
			design.name,
			"[size == size32x32 ? "" : "[size] "][design.id]"
		)

	// Ensure id cache is included for decompression
	var/flat_id_cache = list()
	for (var/id in id_cache)
		flat_id_cache += id

	.["static_data"] = list(
		"node_cache" = node_cache,
		"design_cache" = design_cache,
		"id_cache" = flat_id_cache
	)

/**
 * Compresses an ID to an integer representation using the id_cache, used for deduplication
 * in sent JSON payloads
 *
 * Arguments:
 * * id - the ID to compress
 */
/datum/computer_file/program/science/proc/compress_id(id)
	if (!id_cache[id])
		id_cache[id] = id_cache_seq
		id_cache_seq += 1
	return id_cache[id]

/datum/computer_file/program/science/proc/research_node(id, mob/user)
	if(!stored_research || !stored_research.available_nodes[id] || stored_research.researched_nodes[id])
		computer.say("Node unlock failed: Either no techweb is found, node is already researched or is not available!")
		return FALSE
	var/datum/techweb_node/tech_node = SSresearch.techweb_node_by_id(id)
	if(!istype(tech_node))
		computer.say("Node unlock failed: Unknown error.")
		return FALSE
	var/list/price = tech_node.get_price(stored_research)
	if(stored_research.can_afford(price))
		user.investigate_log("researched [id]([json_encode(price)]) on techweb id [stored_research.id] via [computer].", INVESTIGATE_RESEARCH)
		if(istype(stored_research, /datum/techweb/science))
			SSblackbox.record_feedback("associative", "science_techweb_unlock", 1, list("id" = "[id]", "name" = tech_node.display_name, "price" = "[json_encode(price)]", "time" = ISOtime()))
		if(stored_research.research_node_id(id))
			computer.say("Successfully researched [tech_node.display_name].")
			var/logname = "Unknown"
			if(HAS_AI_ACCESS(user))
				logname = "AI [user.name]"
			if(iscyborg(user))
				logname = "CYBORG [user.name]"
			if(iscarbon(user))
				var/obj/item/card/id/idcard = user.get_active_held_item()
				if(istype(idcard))
					logname = "[idcard.registered_name]"
			if(ishuman(user))
				var/mob/living/carbon/human/human_user = user
				var/obj/item/worn = human_user.wear_id
				if(istype(worn))
					var/obj/item/card/id/id_card_of_human_user = worn.GetID()
					if(istype(id_card_of_human_user))
						logname = "[id_card_of_human_user.registered_name]"
			stored_research.research_logs += list(list(
				"node_name" = tech_node.display_name,
				"node_cost" = price[TECHWEB_POINT_TYPE_GENERIC],
				"node_researcher" = logname,
				"node_research_location" = "[get_area(computer)] ([user.x],[user.y],[user.z])",
			))
			return TRUE
		else
			computer.say("Failed to research node: Internal database error!")
			return FALSE
	computer.say("Not enough research points...")
	return FALSE
