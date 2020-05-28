var/global/nttransfer_uid = 0

/datum/computer_file/program/nttransfer
	filename = "nttransfer"
	filedesc = "РобКо P2P"
	extended_desc = "Программа для двухсторонней связи между терминалами."
	program_icon_state = "comm_logs"
	size = 7
	requires_ntnet = 1
	requires_ntnet_feature = NTNET_PEERTOPEER
	network_destination = "другиее терминалы в  двухсторонней сети"
	available_on_ntnet = 1

	var/error = ""										// Error screen
	var/server_password = ""							// Optional password to download the file.
	var/datum/computer_file/provided_file = null		// File which is provided to clients.
	var/datum/computer_file/downloaded_file = null		// File which is being downloaded
	var/list/connected_clients = list()					// List of connected clients.
	var/datum/computer_file/program/nttransfer/remote	// Client var, specifies who are we downloading from.
	var/download_completion = 0							// Download progress in GQ
	var/download_netspeed = 0							// Our connectivity speed in GQ/s
	var/actual_netspeed = 0								// Displayed in the UI, this is the actual transfer speed.
	var/unique_token 									// UID of this program
	var/upload_menu = 0									// Whether we show the program list and upload menu

/datum/computer_file/program/nttransfer/New()
	unique_token = nttransfer_uid
	nttransfer_uid++
	..()

/datum/computer_file/program/nttransfer/process_tick()
	// Server mode
	update_netspeed()
	if(provided_file)
		for(var/datum/computer_file/program/nttransfer/C in connected_clients)
			// Transfer speed is limited by device which uses slower connectivity.
			// We can have multiple clients downloading at same time, but let's assume we use some sort of multicast transfer
			// so they can all run on same speed.
			C.actual_netspeed = min(C.download_netspeed, download_netspeed)
			C.download_completion += C.actual_netspeed
			if(C.download_completion >= provided_file.size)
				C.finish_download()
	else if(downloaded_file) // Client mode
		if(!remote)
			crash_download("Соединение прекращено")

/datum/computer_file/program/nttransfer/kill_program(forced = FALSE)
	if(downloaded_file) // Client mode, clean up variables for next use
		finalize_download()

	if(provided_file) // Server mode, disconnect all clients
		for(var/datum/computer_file/program/nttransfer/P in connected_clients)
			P.crash_download("Соединение прекращено удалённым сервером")
		downloaded_file = null
	..(forced)

/datum/computer_file/program/nttransfer/proc/update_netspeed()
	download_netspeed = 0
	switch(ntnet_status)
		if(1)
			download_netspeed = NTNETSPEED_LOWSIGNAL
		if(2)
			download_netspeed = NTNETSPEED_HIGHSIGNAL
		if(3)
			download_netspeed = NTNETSPEED_ETHERNET

// Finishes download and attempts to store the file on HDD
/datum/computer_file/program/nttransfer/proc/finish_download()
	var/obj/item/weapon/computer_hardware/hard_drive/hard_drive = computer.all_components[MC_HDD]
	if(!computer || !hard_drive || !hard_drive.store_file(downloaded_file))
		error = "Ошибка: Невозможно сохранить файл"
	finalize_download()

//  Crashes the download and displays specific error message
/datum/computer_file/program/nttransfer/proc/crash_download(var/message)
	error = message ? message : "Во время загрузки произошла неизвестная ошибка"
	finalize_download()

// Cleans up variables for next use
/datum/computer_file/program/nttransfer/proc/finalize_download()
	if(remote)
		remote.connected_clients.Remove(src)
	downloaded_file = null
	remote = null
	download_completion = 0


/datum/computer_file/program/nttransfer/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = 0, datum/tgui/master_ui = null, datum/ui_state/state = default_state)

	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if (!ui)

		var/datum/asset/assets = get_asset_datum(/datum/asset/simple/headers)
		assets.send(user)


		ui = new(user, src, ui_key, "ntnet_transfer", "РобКо P2P", 575, 700, state = state)
		ui.open()
		ui.set_autoupdate(state = 1)

/datum/computer_file/program/nttransfer/ui_act(action, params)
	if(..())
		return 1
	switch(action)
		if("PRG_downloadfile")
			for(var/datum/computer_file/program/nttransfer/P in ntnet_global.fileservers)
				if("[P.unique_token]" == params["id"])
					remote = P
					break
			if(!remote || !remote.provided_file)
				return
			if(remote.server_password)
				var/pass = reject_bad_text(input(usr, "Авторизация:", "Введите пароль"))
				if(pass != remote.server_password)
					error = "Ошибка"
					return
			downloaded_file = remote.provided_file.clone()
			remote.connected_clients.Add(src)
			return 1
		if("PRG_reset")
			error = ""
			upload_menu = 0
			finalize_download()
			if(src in ntnet_global.fileservers)
				ntnet_global.fileservers.Remove(src)
			for(var/datum/computer_file/program/nttransfer/T in connected_clients)
				T.crash_download("Удаленный сервер принудительно закрыл соединение")
			provided_file = null
			return 1
		if("PRG_setpassword")
			var/pass = reject_bad_text(input(usr, "Введите новое имя сервера или введите 'none' для отключения пароля.", "РобКо охранные системы", "none"))
			if(!pass)
				return
			if(pass == "none")
				server_password = ""
				return
			server_password = pass
			return 1
		if("PRG_uploadfile")
			var/obj/item/weapon/computer_hardware/hard_drive/hard_drive = computer.all_components[MC_HDD]
			for(var/datum/computer_file/F in hard_drive.stored_files)
				if("[F.uid]" == params["id"])
					if(F.unsendable)
						error = "Ошибка: Файл зашифрован"
						return
					if(istype(F, /datum/computer_file/program))
						var/datum/computer_file/program/P = F
						if(!P.can_run(usr,transfer = 1))
							error = "Ошибка: Невозможно обновить файл"
					provided_file = F
					ntnet_global.fileservers.Add(src)
					return
			error = "Ошибка: Файл не обнаружен"
			return 1
		if("PRG_uploadmenu")
			upload_menu = 1


/datum/computer_file/program/nttransfer/ui_data(mob/user)

	var/list/data = get_header_data()

	if(error)
		data["error"] = error
	else if(downloaded_file)
		data["downloading"] = 1
		data["download_size"] = downloaded_file.size
		data["download_progress"] = download_completion
		data["download_netspeed"] = actual_netspeed
		data["download_name"] = "[downloaded_file.filename].[downloaded_file.filetype]"
	else if (provided_file)
		data["uploading"] = 1
		data["upload_uid"] = unique_token
		data["upload_clients"] = connected_clients.len
		data["upload_haspassword"] = server_password ? 1 : 0
		data["upload_filename"] = "[provided_file.filename].[provided_file.filetype]"
	else if (upload_menu)
		var/list/all_files[0]
		var/obj/item/weapon/computer_hardware/hard_drive/hard_drive = computer.all_components[MC_HDD]
		for(var/datum/computer_file/F in hard_drive.stored_files)
			all_files.Add(list(list(
			"uid" = F.uid,
			"filename" = "[F.filename].[F.filetype]",
			"size" = F.size
			)))
		data["upload_filelist"] = all_files
	else
		var/list/all_servers[0]
		for(var/datum/computer_file/program/nttransfer/P in ntnet_global.fileservers)
			all_servers.Add(list(list(
			"uid" = P.unique_token,
			"filename" = "[P.provided_file.filename].[P.provided_file.filetype]",
			"size" = P.provided_file.size,
			"haspassword" = P.server_password ? 1 : 0
			)))
		data["servers"] = all_servers

	return data