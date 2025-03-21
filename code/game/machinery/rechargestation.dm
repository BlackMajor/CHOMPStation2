/obj/machinery/recharge_station
	name = "cyborg recharging station"
	desc = "A heavy duty rapid charging system, designed to quickly recharge cyborg power reserves."
	icon = 'icons/obj/objects.dmi'
	icon_state = "borgcharger0"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	circuit = /obj/item/circuitboard/recharge_station
	use_power = USE_POWER_IDLE
	idle_power_usage = 50
	var/mob/occupant = null
	var/obj/item/cell/cell = null
	var/icon_update_tick = 0	// Used to rebuild the overlay only once every 10 ticks
	var/charging = 0

	var/charging_power			// W. Power rating used for charging the cyborg. 120 kW if un-upgraded
	var/restore_power_active	// W. Power drawn from APC when an occupant is charging. 40 kW if un-upgraded
	var/restore_power_passive	// W. Power drawn from APC when idle. 7 kW if un-upgraded
	var/weld_rate = 0			// How much brute damage is repaired per tick
	var/wire_rate = 0			// How much burn damage is repaired per tick

	var/weld_power_use = 2300	// power used per point of brute damage repaired. 2.3 kW ~ about the same power usage of a handheld arc welder
	var/wire_power_use = 500	// power used per point of burn damage repaired.

/obj/machinery/recharge_station/Initialize(mapload)
	. = ..()
	default_apply_parts()
	cell = default_use_hicell()
	update_icon()

/obj/machinery/recharge_station/proc/has_cell_power()
	return cell && cell.percent() > 0

/obj/machinery/recharge_station/process()
	if(stat & (BROKEN))
		return
	if(!cell) // Shouldn't be possible, but sanity check
		return

	if((stat & NOPOWER) && !has_cell_power()) // No power and cell is dead.
		if(icon_update_tick)
			icon_update_tick = 0 //just rebuild the overlay once more only
			update_icon()
		return

	//First, draw from the internal power cell to recharge/repair/etc the occupant
	if(occupant)
		process_occupant()

	//Then, if external power is available, recharge the internal cell
	var/recharge_amount = 0
	if(!(stat & NOPOWER))
		// Calculating amount of power to draw
		recharge_amount = (occupant ? restore_power_active : restore_power_passive) * CELLRATE

		recharge_amount = cell.give(recharge_amount)
		use_power(recharge_amount / CELLRATE)
	else
		// Since external power is offline, draw operating current from the internal cell
		cell.use(get_power_usage() * CELLRATE)

	if(icon_update_tick >= 10)
		icon_update_tick = 0
	else
		icon_update_tick++

	if(occupant || recharge_amount)
		update_icon()

//Processes the occupant, drawing from the internal power cell if needed.
/obj/machinery/recharge_station/proc/process_occupant()
	if(isrobot(occupant))
		var/mob/living/silicon/robot/R = occupant
		var/overcharged = FALSE
		if(R.cell.maxcharge < R.cell.charge)
			overcharged = TRUE
		if(R.module && !overcharged)
			R.module.respawn_consumable(R, charging_power * CELLRATE / 250) //consumables are magical, apparently
		if(R.cell && !R.cell.fully_charged() && !overcharged)
			var/diff = min(R.cell.maxcharge - R.cell.charge, charging_power * CELLRATE) // Capped by charging_power / tick
			var/charge_used = cell.use(diff)
			R.cell.give(charge_used)

		//Lastly, attempt to repair the cyborg if enabled
		if(weld_rate && R.getBruteLoss() && cell.checked_use(weld_power_use * weld_rate * CELLRATE))
			R.adjustBruteLoss(-weld_rate)
		if(wire_rate && R.getFireLoss() && cell.checked_use(wire_power_use * wire_rate * CELLRATE))
			R.adjustFireLoss(-wire_rate)

	//VOREStation Add Start
	else if(ispAI(occupant))
		var/mob/living/silicon/pai/P = occupant

		if(P.nutrition < 400)
			P.nutrition = min(P.nutrition+10, 400)
			cell.use(7000/450*10)
	//VOREStation Add End

	else if(ishuman(occupant))
		var/mob/living/carbon/human/H = occupant

		if(H.isSynthetic())
			// In case they somehow end up with positive values for otherwise unobtainable damage...
			if(H.getToxLoss() > 0)
				H.adjustToxLoss(-(rand(1,3)))
			if(H.getOxyLoss() > 0)
				H.adjustOxyLoss(-(rand(1,3)))
			if(H.getCloneLoss() > 0)
				H.adjustCloneLoss(-(rand(1,3)))
			if(H.getBrainLoss() > 0)
				H.adjustBrainLoss(-(rand(1,3)))

			// Also recharge their internal battery.
			if(H.isSynthetic() && H.nutrition < 500) //VOREStation Edit
				H.nutrition = min(H.nutrition+(10*(1-min(H.species.synthetic_food_coeff, 0.9))), 500) //VOREStation Edit
				cell.use(7000/450*10)

			// And clear up radiation
			if(H.radiation > 0 || H.accumulated_rads > 0)
				H.radiation = max(H.radiation - 25, 0)
				H.accumulated_rads = max(H.accumulated_rads - 25, 0)

		if(H.wearing_rig) // stepping into a borg charger to charge your rig and fix your shit
			var/obj/item/rig/wornrig = H.get_rig()
			if(wornrig) // just to make sure
				for(var/obj/item/rig_module/storedmod in wornrig.installed_modules)
					if(weld_rate && storedmod.damage && cell.checked_use(weld_power_use * weld_rate * CELLRATE))
						to_chat(H, span_notice("[storedmod] is repaired!"))
						storedmod.damage = 0
				if(wornrig.chest)
					var/obj/item/clothing/suit/space/rig/rigchest = wornrig.chest
					if(weld_rate && rigchest.damage && cell.checked_use(weld_power_use * weld_rate * CELLRATE))
						rigchest.breaches = list()
						rigchest.calc_breach_damage()
						to_chat(H, span_notice("[rigchest] is repaired!"))
				if(wornrig.cell)
					var/obj/item/cell/rigcell = wornrig.cell
					var/diff = min(rigcell.maxcharge - rigcell.charge, charging_power * CELLRATE) // Capped by charging_power / tick
					var/charge_used = cell.use(diff)
					rigcell.give(charge_used)

/obj/machinery/recharge_station/examine(mob/user)
	. = ..()
	. += "The charge meter reads: [round(chargepercentage())]%"

/obj/machinery/recharge_station/proc/chargepercentage()
	if(!cell)
		return 0
	return cell.percent()

/obj/machinery/recharge_station/relaymove(mob/user as mob)
	if(user.stat)
		return
	go_out()
	return

/obj/machinery/recharge_station/emp_act(severity)
	if(occupant)
		occupant.emp_act(severity)
		go_out()
	if(cell)
		cell.emp_act(severity)
	..(severity)

/obj/machinery/recharge_station/attackby(var/obj/item/O as obj, var/mob/user as mob)
	if(!occupant)
		if(default_deconstruction_screwdriver(user, O))
			return
		if(default_deconstruction_crowbar(user, O))
			return
		if(default_part_replacement(user, O))
			return
		if (istype(O, /obj/item/grab) && get_dist(src,user)<2)
			var/obj/item/grab/G = O
			if(isliving(G.affecting))
				var/mob/living/M = G.affecting
				qdel(O)
				go_in(M)

	..()

/obj/machinery/recharge_station/MouseDrop_T(var/mob/target, var/mob/user)
	if(user.stat || user.lying || !Adjacent(user) || !target.Adjacent(user))
		return

	go_in(target)

/obj/machinery/recharge_station/RefreshParts()
	..()
	var/man_rating = 0
	var/cap_rating = 0

	for(var/obj/item/stock_parts/P in component_parts)
		if(istype(P, /obj/item/stock_parts/capacitor))
			cap_rating += P.rating
		if(istype(P, /obj/item/stock_parts/manipulator))
			man_rating += P.rating
	cell = locate(/obj/item/cell) in component_parts

	charging_power = 40000 + 40000 * cap_rating
	restore_power_active = 10000 + 15000 * cap_rating
	restore_power_passive = 5000 + 1000 * cap_rating
	weld_rate = max(0, man_rating - 3)
	wire_rate = max(0, man_rating - 5)

	desc = initial(desc)
	desc += " Uses a dedicated internal power cell to deliver [charging_power]W when in use."
	if(weld_rate)
		desc += "<br>It is capable of repairing structural damage."
	if(wire_rate)
		desc += "<br>It is capable of repairing burn damage."

/obj/machinery/recharge_station/proc/build_overlays()
	cut_overlays()
	switch(round(chargepercentage()))
		if(1 to 20)
			add_overlay("statn_c0")
		if(21 to 40)
			add_overlay("statn_c20")
		if(41 to 60)
			add_overlay("statn_c40")
		if(61 to 80)
			add_overlay("statn_c60")
		if(81 to 98)
			add_overlay("statn_c80")
		if(99 to 110)
			add_overlay("statn_c100")

/obj/machinery/recharge_station/update_icon()
	..()
	if(stat & BROKEN)
		icon_state = "borgcharger0"
		return

	if(occupant)
		if((stat & NOPOWER) && !has_cell_power())
			icon_state = "borgcharger2"
		else
			icon_state = "borgcharger1"
	else
		icon_state = "borgcharger0"

	if(icon_update_tick == 0)
		build_overlays()

/obj/machinery/recharge_station/Bumped(var/mob/living/L)
	go_in(L)

/obj/machinery/recharge_station/proc/go_in(var/mob/living/L)

	if(occupant)
		return

	if(isrobot(L))
		var/mob/living/silicon/robot/R = L

		if(R.incapacitated())
			return

		if(!R.cell)
			return

		if(istype(R, /mob/living/silicon/robot/platform))
			to_chat(R, span_warning("You are too large to fit into \the [src]."))
			return

		add_fingerprint(R)
		R.reset_view(src)
		R.forceMove(src)
		occupant = R
		update_icon()
		return 1

	//VOREStation Add Start
	else if(ispAI(L))
		var/mob/living/silicon/pai/P = L

		if(P.incapacitated())
			return

		add_fingerprint(P)
		P.reset_view(src)
		P.forceMove(src)
		occupant = P
		update_icon()
		return 1
	//VOREStation Add End

	else if(istype(L,  /mob/living/carbon/human))
		var/mob/living/carbon/human/H = L
		if(H.isSynthetic() || H.wearing_rig)
			add_fingerprint(H)
			H.reset_view(src)
			H.forceMove(src)
			occupant = H
			update_icon()
			return 1
	else
		return

/obj/machinery/recharge_station/proc/go_out()
	if(!occupant)
		return

	occupant.forceMove(src.loc)
	occupant.reset_view()
	occupant = null
	update_icon()

/obj/machinery/recharge_station/verb/move_eject()
	set category = "Object"
	set name = "Eject Recharger"
	set src in oview(1)

	if(usr.incapacitated() || !isliving(usr))
		return

	go_out()
	add_fingerprint(usr)
	return

/obj/machinery/recharge_station/verb/move_inside()
	set category = "Object"
	set name = "Enter Recharger"
	set src in oview(1)

	if(usr.incapacitated() || !isliving(usr))
		return

	go_in(usr)

/obj/machinery/recharge_station/ghost_pod_recharger
	name = "drone pod"
	desc = "This is a pod which used to contain a drone... Or maybe it still does?"
	icon = 'icons/obj/structures.dmi'

/obj/machinery/recharge_station/ghost_pod_recharger/update_icon()
	..()
	if(stat & BROKEN)
		icon_state = "borg_pod_closed"
		desc = "It appears broken..."
		return

	if(occupant)
		if((stat & NOPOWER) && !has_cell_power())
			icon_state = "borg_pod_closed"
			desc = "It appears to be unpowered..."
		else
			icon_state = "borg_pod_closed"
	else
		icon_state = "borg_pod_opened"

	if(icon_update_tick == 0)
		build_overlays()
