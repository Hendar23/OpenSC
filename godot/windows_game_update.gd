extends RefCounted

const STAGING := "user://game-updates"
const INSTALL_MARKER := "OpenSC.installed"

static func is_installed() -> bool:
	if OS.get_name() != "Windows" or OS.has_feature("editor"):
		return false
	var install_dir := OS.get_executable_path().get_base_dir()
	return FileAccess.file_exists(install_dir.path_join(INSTALL_MARKER))

static func start(owner: Node, release: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STAGING)) != OK:
		return false
	var staging := DirAccess.open(STAGING)
	if staging == null:
		return false
	for file in staging.get_files():
		if file.begins_with("OpenSC-Update-") and file.ends_with(".exe"):
			if Time.get_unix_time_from_system() - FileAccess.get_modified_time(STAGING.path_join(file)) > 86400:
				staging.remove(file)
	var nonce := Crypto.new().generate_random_bytes(16)
	if nonce.size() != 16:
		return false
	var path := ProjectSettings.globalize_path(STAGING.path_join("OpenSC-Update-%s.exe" % nonce.hex_encode()))
	var http := HTTPRequest.new()
	http.timeout = 180.0
	http.body_size_limit = 512 * 1024 * 1024
	http.download_file = path
	owner.add_child(http)
	var requested := http.request(release.installer_url, ["User-Agent: OpenSC"])
	var downloaded := false
	if requested == OK:
		var response: Array = await http.request_completed
		downloaded = response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200
	http.queue_free()
	if downloaded and matches_digest(path, release.installer_sha256):
		var install_dir := OS.get_executable_path().get_base_dir()
		var launched := OS.create_process(path, ["/SILENT", "/NORESTART", "/NOCLOSEAPPLICATIONS",
			"/OPENSCUPDATEPID=%d" % OS.get_process_id(), "/OPENSCUPDATEDIR=" + install_dir.replace("/", "\\")])
		if launched > 0:
			return true
	DirAccess.remove_absolute(path)
	return false

static func matches_digest(path: String, sha256: String) -> bool:
	return not sha256.is_empty() and FileAccess.get_sha256(path) == sha256
