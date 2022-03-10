/obj/structure/ladder/vine
	name = "vines"
	desc = "Earthy vines. You can probably climb these."
	icon_state = "vines"
	icon = 'icons/obj/structures/multiz_ch.dmi'

/obj/structure/ladder/vine/autoplace
	name = "vine placer (place on top most z)"

/obj/structure/ladder/vine/autoplace/Initialize()
	var/turf/T = GetBelow(src)
	if(T)
		message_admins("Yeah")
		var/obj/structure/ladder/vine/V = new(T.loc)
		V.dir = src.dir
		V.update_icon()
	var/obj/structure/ladder/vine/V = new(src.loc)
	V.dir = src.dir
	V.update_icon()
	qdel(src)

/obj/structure/ladder/vine/climbLadder(var/mob/M, var/obj/target_ladder)
	var/direction = (target_ladder == target_up ? "up" : "down")
	M.visible_message("<b>\The [M]</b> begins climbing [direction] \the [src]!",
		"You begin climbing [direction] \the [src]!",
		"You hear rustling of fibrous plants being wrangled.")

	target_ladder.audible_message("<span class='notice'>You hear something coming [direction] \the [src]</span>", runemessage = "rustle rustle")

	if(do_after(M, climb_time, src))
		var/turf/T = get_turf(target_ladder)
		for(var/atom/A in T)
			if(!A.CanPass(M, M.loc, 1.5, 0))
				to_chat(M, "<span class='notice'>\The [A] is blocking \the [src].</span>")
				return FALSE
		return M.forceMove(T) //VOREStation Edit - Fixes adminspawned ladders


/obj/structure/ladder/vine/update_icon()
	icon_state = "vines"

/obj/structure/ladder/vine/CanFallThru(atom/movable/mover as mob|obj, turf/target as turf)
	if(target.z >= z)
		return TRUE
	else if(istype(mover) && mover.checkpass(PASSGRILLE))
		return TRUE
	if(!isturf(mover.loc))
		return FALSE
	else
		return FALSE

/obj/structure/ladder/vine/CheckFall(var/atom/movable/falling_atom)
	if(istype(falling_atom) && falling_atom.checkpass(PASSGRILLE))
		return FALSE
	return falling_atom.fall_impact(src)