#define BATON_COOLDOWN 3.5 SECONDS

/mob/living/simple_animal/bot/ed209
	name = "\improper ED-209 Security Robot"
	desc = "A security robot.  He looks less than thrilled."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "ed2090"
	density = TRUE
	anchored = FALSE
	health = 150
	maxHealth = 150
	damage_coeff = list(BRUTE = 0.5, BURN = 0.7, TOX = 0, CLONE = 0, STAMINA = 0, OXY = 0)
	obj_damage = 60
	environment_smash = ENVIRONMENT_SMASH_WALLS //Walls can't stop THE LAW
	mob_size = MOB_SIZE_LARGE

	radio_channel = "Security"
	bot_type = SEC_BOT
	bot_filter = RADIO_SECBOT
	model = "ED-209"
	bot_purpose = "seek out criminals, handcuff them, and report their location to security"
	req_access = list(ACCESS_SECURITY)
	window_id = "autoed209"
	window_name = "Automatic Security Unit v2.6"
	data_hud_type = DATA_HUD_SECURITY_ADVANCED

	allow_pai = FALSE

	var/lastfired = 0
	var/shot_delay = 3 //.3 seconds between shots
	var/lasercolor = ""
	var/disabled = FALSE //A holder for if it needs to be disabled, if true it will not seach for targets, shoot at targets, or move, currently only used for lasertag

	var/mob/living/carbon/target
	var/oldtarget_name
	var/threatlevel = 0
	var/target_lastloc //Loc of target when arrested.
	var/last_found //There's a delay
	var/declare_arrests = TRUE //When making an arrest, should it notify everyone wearing sechuds?
	var/idcheck = FALSE //If true, arrest people with no IDs
	var/weapons_check = TRUE //If true, arrest people for weapons if they don't have access
	var/check_records = TRUE //Does it check security records?
	var/no_handcuffs = FALSE //If true, don't handcuff
	var/projectile = /obj/item/projectile/beam/disabler //Holder for projectile type
	var/shoot_sound = 'sound/weapons/taser.ogg'
	var/baton_delayed = FALSE
	var/obj/item/melee/baton/infinite_cell/baton = null // stunbaton bot uses to melee attack
	var/currently_cuffing = FALSE // TRUE if we're cuffing someone right now

/mob/living/simple_animal/bot/ed209/Initialize(mapload, created_name, created_lasercolor)
	. = ..()
	baton = new(src)
	if(created_name)
		name = created_name
	if(created_lasercolor)
		lasercolor = created_lasercolor
	icon_state = "[lasercolor]ed209[on]"
	set_weapon() //giving it the right projectile and firing sound.
	setup_access()

	if(lasercolor)
		shot_delay = 6 //Longer shot delay because JESUS CHRIST
		check_records = FALSE //Don't actively target people set to arrest
		no_handcuffs = TRUE //Don't even try to cuff
		declare_arrests = FALSE // Don't spam sec
		req_access = list(ACCESS_MAINT_TUNNELS, ACCESS_THEATRE, ACCESS_ROBOTICS)

		if(created_name == initial(name) || !created_name)
			if(lasercolor == "b")
				name = pick("BLUE BALLER","SANIC","BLUE KILLDEATH MURDERBOT")
			else if(lasercolor == "r")
				name = pick("RED RAMPAGE","RED ROVER","RED KILLDEATH MURDERBOT")

/mob/living/simple_animal/bot/ed209/Destroy()
	QDEL_NULL(baton)
	return ..()

/mob/living/simple_animal/bot/ed209/proc/setup_access()
	if(access_card)
		var/datum/job/detective/J = new/datum/job/detective
		access_card.access += J.get_access()
		prev_access = access_card.access

/mob/living/simple_animal/bot/ed209/turn_on()
	. = ..()
	icon_state = "[lasercolor]ed209[on]"
	mode = BOT_IDLE

/mob/living/simple_animal/bot/ed209/turn_off()
	..()
	icon_state = "[lasercolor]ed209[on]"

/mob/living/simple_animal/bot/ed209/bot_reset()
	..()
	target = null
	oldtarget_name = null
	anchored = FALSE
	currently_cuffing = FALSE
	walk_to(src,0)
	set_path(null)
	last_found = world.time
	set_weapon()

/mob/living/simple_animal/bot/ed209/set_custom_texts()
	text_hack = "You disable [name]'s combat inhibitor."
	text_dehack = "You restore [name]'s combat inhibitor."
	text_dehack_fail = "[name] ignores your attempts to restrict [p_them()]!"

/mob/living/simple_animal/bot/ed209/show_controls(mob/user)
	ui_interact(user)

/mob/living/simple_animal/bot/ed209/ui_state(mob/user)
	return GLOB.default_state

/mob/living/simple_animal/bot/ed209/ui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "BotSecurity", name)
		ui.open()

/mob/living/simple_animal/bot/ed209/ui_data(mob/user)
	var/list/data = ..()
	data["check_id"] = idcheck
	data["check_weapons"] = weapons_check
	data["check_warrant"] = check_records
	data["arrest_mode"] = no_handcuffs // detain or arrest
	data["arrest_declare"] = declare_arrests // announce arrests on radio
	return data

/mob/living/simple_animal/bot/ed209/ui_act(action, params)
	if(..())
		return
	if(topic_denied(usr))
		to_chat(usr, "<span class='warning'>[src]'s interface is not responding!</span>")
		return
	add_fingerprint(usr)
	. = TRUE
	switch(action)
		if("power")
			if(on)
				turn_off()
			else
				turn_on()
		if("autopatrol")
			auto_patrol = !auto_patrol
			bot_reset()
		if("hack")
			handle_hacking(usr)
		if("disableremote")
			remote_disabled = !remote_disabled
		if("authweapon")
			weapons_check = !weapons_check
		if("authid")
			idcheck = !idcheck
		if("authwarrant")
			check_records = !check_records
		if("arrtype")
			no_handcuffs = !no_handcuffs
		if("arrdeclare")
			declare_arrests = !declare_arrests
		if("ejectpai")
			ejectpai()


/mob/living/simple_animal/bot/ed209/topic_denied(mob/user)
	if(lasercolor && ishuman(user))
		var/mob/living/carbon/human/H = user
		if((lasercolor == "b") && (istype(H.wear_suit, /obj/item/clothing/suit/redtag))) //Opposing team cannot operate it
			return TRUE
		else if((lasercolor == "r") && (istype(H.wear_suit, /obj/item/clothing/suit/bluetag)))
			return TRUE
	return ..()

/mob/living/simple_animal/bot/ed209/proc/retaliate(mob/living/carbon/human/H)
	threatlevel = H.assess_threat(src)
	threatlevel += 6
	if(threatlevel >= 4)
		target = H
		mode = BOT_HUNT

/mob/living/simple_animal/bot/ed209/attack_hand(mob/living/carbon/human/H)
	if(H.a_intent == INTENT_HARM)
		retaliate(H)
	return ..()

/mob/living/simple_animal/bot/ed209/attackby(obj/item/W, mob/user, params)
	..()
	if(W.force && !target && W.damtype != STAMINA)
		retaliate(user)
		if(lasercolor)//To make up for the fact that lasertag bots don't hunt
			shootAt(user)

/mob/living/simple_animal/bot/ed209/emag_act(mob/user)
	..()
	if(emagged)
		if(user)
			to_chat(user, "<span class='warning'>You short out [src]'s target assessment circuits.</span>")
			oldtarget_name = user.name
		audible_message("<span class='danger'>[src] buzzes oddly!</span>")
		declare_arrests = FALSE
		icon_state = "[lasercolor]ed209[on]"
		set_weapon()

/mob/living/simple_animal/bot/ed209/bullet_act(obj/item/projectile/Proj)
	if(istype(Proj ,/obj/item/projectile/beam)||istype(Proj,/obj/item/projectile/bullet))
		if((Proj.damage_type == BURN) || (Proj.damage_type == BRUTE))
			if(!Proj.nodamage && Proj.damage < src.health)
				retaliate(Proj.firer)
	..()

/mob/living/simple_animal/bot/ed209/handle_automated_action()
	if(!..())
		return

	if(disabled)
		return

	ed209_ai()


/mob/living/simple_animal/bot/ed209/proc/ed209_ai()
	var/list/targets = list()
	for(var/mob/living/carbon/C in view(7, src)) //Let's find us a target
		var/threatlevel = 0
		if(C.stat || !(mobility_flags & MOBILITY_MOVE))
			continue
		threatlevel = C.assess_threat(src, lasercolor)
		//speak(C.real_name + text(": threat: []", threatlevel))
		if(threatlevel < 4)
			continue

		var/dst = get_dist(src, C)
		if(dst <= 1 || dst > 7)
			continue

		targets += C
	if(length(targets))
		var/mob/living/carbon/t = pick(targets)
		if(t.stat != DEAD && !HAS_TRAIT(t, TRAIT_FLOORED) && !t.handcuffed) //we don't shoot people who are dead, cuffed or lying down.
			shootAt(t)
	switch(mode)

		if(BOT_IDLE)		// idle
			walk_to(src,0)
			set_path(null)
			if(!lasercolor) //lasertag bots don't want to arrest anyone
				if(find_new_target())
					return	// see if any criminals are in range
			if(!mode && auto_patrol)	// still idle, and set to patrol
				mode = BOT_START_PATROL	// switch to patrol mode

		if(BOT_HUNT)		// hunting for perp
			// if can't reach perp for long enough, go idle
			if(frustration >= 8)
				walk_to(src, 0)
				set_path(null)
				back_to_idle()
				return

			if(!target)		// make sure target exists
				back_to_idle()
				return

			if(Adjacent(target) && isturf(target.loc) && !baton_delayed)	// if right next to perp
				stun_attack(target)
				if(!lasercolor)
					mode = BOT_PREP_ARREST
					anchored = TRUE
					target_lastloc = target.loc
					return
				mode = BOT_HUNT
				target = null
				target_lastloc = null
				return

			try_chasing_target(target)

		if(BOT_PREP_ARREST)		// preparing to arrest target

			// see if he got away. If he's no no longer adjacent or inside a closet or about to get up, we hunt again.
			if(!Adjacent(target) || !isturf(target.loc) || world.time - target.stam_regen_start_time < 4 SECONDS && target.getStaminaLoss() <= 100)
				back_to_hunt()
				return

			if(!(iscarbon(target) && target.canBeHandcuffed()))
				back_to_idle()
				return

			if(no_handcuffs) // should we not cuff?
				return

			if(currently_cuffing)
				return

			if(!target.handcuffed)
				cuff(target)
				return

			back_to_idle()

		if(BOT_ARREST)
			if(!target || target.handcuffed)
				back_to_idle()
				return

			if(!Adjacent(target) || !isturf(target.loc) || (target.loc != target_lastloc && world.time - target.stam_regen_start_time < 4 SECONDS && target.getStaminaLoss() <= 100)) //if he's changed loc and about to get up or not adjacent or got into a closet, we prep arrest again.
				back_to_hunt()
				return

			mode = BOT_PREP_ARREST
			anchored = FALSE

		if(BOT_START_PATROL)
			if(find_new_target())
				return
			start_patrol()

		if(BOT_PATROL)
			if(find_new_target())
				return
			bot_patrol()


	return

/mob/living/simple_animal/bot/ed209/proc/back_to_idle()
	anchored = FALSE
	mode = BOT_IDLE
	target = null
	last_found = world.time
	frustration = 0
	INVOKE_ASYNC(src, PROC_REF(handle_automated_action))

/mob/living/simple_animal/bot/ed209/proc/back_to_hunt()
	anchored = FALSE
	frustration = 0
	mode = BOT_HUNT
	INVOKE_ASYNC(src, PROC_REF(handle_automated_action))

// look for a criminal in view of the bot

/mob/living/simple_animal/bot/ed209/proc/find_new_target()
	if(disabled)
		return FALSE
	anchored = FALSE
	threatlevel = 0
	for(var/mob/living/carbon/C in view(7,src)) //Let's find us a criminal
		if((C.stat) || (C.handcuffed))
			continue

		if((C.name == oldtarget_name) && (world.time < last_found + 100))
			continue

		threatlevel = C.assess_threat(src, lasercolor)

		if(!threatlevel || threatlevel < 4)
			continue

		target = C
		oldtarget_name = C.name
		speak("Level [threatlevel] infraction alert!")
		playsound(loc, pick('sound/voice/ed209_20sec.ogg', 'sound/voice/edplaceholder.ogg'), 50, FALSE)
		visible_message("<b>[src]</b> points at [C.name]!")
		mode = BOT_HUNT
		INVOKE_ASYNC(src, PROC_REF(handle_automated_action))
		return TRUE
	return FALSE

/mob/living/simple_animal/bot/ed209/proc/check_for_weapons(obj/item/slot_item)
	if(slot_item && slot_item.needs_permit)
		return 1
	return 0

/mob/living/simple_animal/bot/ed209/explode()
	visible_message("<span class='userdanger'>[src] blows apart!</span>")
	var/turf/explode_turf = get_turf(src)

	var/obj/item/ed209_assembly/pierced_helmet = new /obj/item/ed209_assembly(explode_turf)
	pierced_helmet.build_step = 1
	pierced_helmet.overlays += image('icons/obj/aibots.dmi', "hs_hole")
	pierced_helmet.created_name = name
	new /obj/item/assembly/prox_sensor(explode_turf)

	switch(lasercolor)
		if("b")
			var/obj/item/gun/energy/laser/tag/blue/ed_gun = new /obj/item/gun/energy/laser/tag/blue(explode_turf)
			ed_gun.cell.charge = 0
			ed_gun.update_icon()
		if("r")
			var/obj/item/gun/energy/laser/tag/red/ed_gun = new /obj/item/gun/energy/laser/tag/red(explode_turf)
			ed_gun.cell.charge = 0
			ed_gun.update_icon()
		else
			var/obj/item/gun/energy/disabler/ed_gun = new /obj/item/gun/energy/disabler(explode_turf)
			ed_gun.cell.charge = 0
			ed_gun.update_icon()

	if(prob(50))
		new /obj/item/robot_parts/l_leg(explode_turf)
		if(prob(25))
			new /obj/item/robot_parts/r_leg(explode_turf)
	if(prob(25))//50% chance for a helmet OR vest
		if(prob(50))
			new /obj/item/clothing/head/helmet(explode_turf)
		else
			switch(lasercolor)
				if("b")
					new /obj/item/clothing/suit/bluetag(explode_turf)
				if("r")
					new /obj/item/clothing/suit/redtag(explode_turf)
				else
					new /obj/item/clothing/suit/armor/vest(explode_turf)

	do_sparks(3, 1, src)

	new /obj/effect/decal/cleanable/blood/oil(loc)
	..()

///Disassembling the bot in a civilized manner with a multitool
/mob/living/simple_animal/bot/ed209/disassemble()
	var/turf/disassemble_turf = get_turf(src)

	var/obj/item/ed209_assembly/pierced_helmet = new /obj/item/ed209_assembly(disassemble_turf)
	pierced_helmet.build_step = 1
	pierced_helmet.overlays += image('icons/obj/aibots.dmi', "hs_hole")
	pierced_helmet.created_name = name
	new /obj/item/assembly/prox_sensor(disassemble_turf)

	switch(lasercolor)
		if("b")
			var/obj/item/gun/energy/laser/tag/blue/ed_gun = new /obj/item/gun/energy/laser/tag/blue(disassemble_turf)
			ed_gun.cell.charge = 0
			ed_gun.update_icon()
		if("r")
			var/obj/item/gun/energy/laser/tag/red/ed_gun = new /obj/item/gun/energy/laser/tag/red(disassemble_turf)
			ed_gun.cell.charge = 0
			ed_gun.update_icon()
		else
			var/obj/item/gun/energy/disabler/ed_gun = new /obj/item/gun/energy/disabler(disassemble_turf)
			ed_gun.cell.charge = 0
			ed_gun.update_icon()

	new /obj/item/robot_parts/l_leg(disassemble_turf)
	new /obj/item/robot_parts/r_leg(disassemble_turf)
	new /obj/item/clothing/head/helmet(disassemble_turf)

	switch(lasercolor)
		if("b")
			new /obj/item/clothing/suit/bluetag(disassemble_turf)
		if("r")
			new /obj/item/clothing/suit/redtag(disassemble_turf)
		else
			new /obj/item/clothing/suit/armor/vest(disassemble_turf)
	qdel(src)

/mob/living/simple_animal/bot/ed209/proc/set_weapon()  //used to update the projectile type and firing sound
	shoot_sound = 'sound/weapons/laser.ogg'
	if(emagged)
		if(lasercolor)
			projectile = /obj/item/projectile/beam/disabler
		else
			projectile = /obj/item/projectile/beam
	else
		if(!lasercolor)
			projectile = /obj/item/projectile/beam/disabler
		else if(lasercolor == "b")
			projectile = /obj/item/projectile/beam/lasertag/bluetag
		else if(lasercolor == "r")
			projectile = /obj/item/projectile/beam/lasertag/redtag

/mob/living/simple_animal/bot/ed209/proc/shootAt(mob/target)
	if(lastfired && world.time - lastfired < shot_delay)
		return
	lastfired = world.time
	var/turf/T = loc
	var/atom/U = (istype(target, /atom/movable) ? target.loc : target)
	if(!U || !T)
		return
	while(!isturf(U))
		U = U.loc
	if(!isturf(T))
		return

	if(!projectile)
		return

	if(!isturf(U))
		return
	var/obj/item/projectile/A = new projectile(loc)
	playsound(loc, shoot_sound, 50, 1)
	A.current = U
	A.yo = U.y - T.y
	A.xo = U.x - T.x
	A.fire()

/mob/living/simple_animal/bot/ed209/attack_alien(mob/living/carbon/alien/user)
	..()
	if(!isalien(target))
		target = user
		mode = BOT_HUNT

/mob/living/simple_animal/bot/ed209/emp_act(severity)

	if(severity==2 && prob(70))
		..(severity-1)
	else
		var/obj/effect/overlay/pulse2 = new/obj/effect/overlay ( loc )
		pulse2.icon = 'icons/effects/effects.dmi'
		pulse2.icon_state = "empdisable"
		pulse2.name = "emp sparks"
		pulse2.anchored = TRUE
		pulse2.dir = pick(GLOB.cardinal)
		QDEL_IN(pulse2, 1 SECONDS)
		var/list/mob/living/carbon/targets = list()
		for(var/mob/living/carbon/C in view(12,src))
			if(C.stat==2)
				continue
			targets += C
		if(length(targets))
			if(prob(50))
				var/mob/toshoot = pick(targets)
				if(toshoot)
					targets-=toshoot
					if(prob(50) && !emagged && !locked)
						emagged = TRUE
						set_weapon()
						shootAt(toshoot)
						emagged = FALSE
						set_weapon()
					else
						shootAt(toshoot)
			else if(prob(50))
				if(length(targets))
					var/mob/toarrest = pick(targets)
					if(toarrest)
						target = toarrest
						mode = BOT_HUNT


/mob/living/simple_animal/bot/ed209/bullet_act(obj/item/projectile/Proj)
	if(!disabled)
		var/lasertag_check = 0
		if(lasercolor == "b")
			if(istype(Proj, /obj/item/projectile/beam/lasertag/redtag))
				lasertag_check++

		else if(lasercolor == "r")
			if(istype(Proj, /obj/item/projectile/beam/lasertag/bluetag))
				lasertag_check++

		if(lasertag_check)
			icon_state = "[lasercolor]ed2090"
			disabled = TRUE
			walk_to(src, 0)
			target = null
			addtimer(CALLBACK(src, PROC_REF(unset_disabled)), 10 SECONDS)
			return TRUE

		else
			..(Proj)

	else
		..(Proj)

/mob/living/simple_animal/bot/ed209/proc/unset_disabled()
	disabled = FALSE
	icon_state = "[lasercolor]ed2091"

/mob/living/simple_animal/bot/ed209/bluetag
	lasercolor = "b"

/mob/living/simple_animal/bot/ed209/redtag
	lasercolor = "r"

/mob/living/simple_animal/bot/ed209/UnarmedAttack(atom/A)
	if(!on)
		return
	if(iscarbon(A))
		var/mob/living/carbon/C = A
		if(!C.IsStunned() || no_handcuffs && !baton_delayed)
			stun_attack(A)
		else if(C.canBeHandcuffed() && !C.handcuffed)
			cuff(A)
	else
		..()

/mob/living/simple_animal/bot/ed209/hitby(atom/movable/AM, skipcatch = FALSE, hitpush = TRUE, blocked = FALSE, datum/thrownthing/throwingdatum)
	if(isitem(AM))
		var/obj/item/I = AM
		var/mob/thrower = locateUID(I.thrownby)
		if(I.throwforce < src.health && ishuman(thrower))
			retaliate(thrower)
	..()

/mob/living/simple_animal/bot/ed209/RangedAttack(atom/A, params)
	if(!on)
		return
	shootAt(A)

/mob/living/simple_animal/bot/ed209/proc/stun_attack(mob/living/carbon/C)
	var/threat = C.assess_threat(src)
	var/prev_intent = a_intent
	a_intent = INTENT_HELP
	baton.attack(C, src)
	a_intent = prev_intent
	baton_delayed = TRUE
	addtimer(VARSET_CALLBACK(src, baton_delayed, FALSE), BATON_COOLDOWN)
	icon_state = "[lasercolor]ed209-c"
	addtimer(VARSET_CALLBACK(src, icon_state, "[lasercolor]ed209[on]"), 2)
	if(declare_arrests)
		var/area/location = get_area(src)
		speak("[no_handcuffs ? "Detaining" : "Arresting"] level [threat] scumbag <b>[C]</b> in [location].", radio_channel)

/mob/living/simple_animal/bot/ed209/proc/cuff(mob/living/carbon/C)
	mode = BOT_ARREST
	playsound(loc, 'sound/weapons/cablecuff.ogg', 30, 1, -2)
	C.visible_message("<span class='danger'>[src] is trying to put zipties on [C]!</span>",\
						"<span class='userdanger'>[src] is trying to put zipties on you!</span>")

	INVOKE_ASYNC(src, PROC_REF(cuff_callback), C)

/mob/living/simple_animal/bot/ed209/proc/cuff_callback(mob/living/carbon/C)
	if(!do_after(src, 6 SECONDS, target = C))
		return
	if(!C.handcuffed && on)
		C.handcuffed = new /obj/item/restraints/handcuffs/cable/zipties/used(C)
		C.update_handcuffed()
	back_to_idle()

#undef BATON_COOLDOWN
