function trim(s)
   return (s:gsub("^%s*(%S+)%s*", "%1"))
end

function openURL()
   
   subprocess = {
      name = "subprocess",
      args = { "powershell", "-Command", "Get-Clipboard", "-Raw" },
      playback_only = false,
      capture_stdout = true,
      capture_stderr = true
   }
   
   mp.osd_message("Getting URL from clipboard...")
   
   r = mp.command_native(subprocess)
   
   --failed getting clipboard data for some reason
   if r.status < 0 then
      mp.osd_message("Failed getting clipboard data!")
      print("Error(string): "..r.error_string)
      print("Error(stderr): "..r.stderr)
   end
   
   url = r.stdout
   
   if not url then
      return
   end
   
   --trim whitespace from string
   url=trim(url)

   if not url then
      mp.osd_message("clipboard empty")
      return
   end
   
   --immediately resume playback after loading URL
   if mp.get_property_bool("core-idle") then
      if not mp.get_property_bool("idle-active") then
         mp.command("keypress space")
      end
   end

   --try opening url
   --will fail if url is not valid
   mp.osd_message("Try Opening URL:\n"..url)
   mp.commandv("loadfile", url, "replace")
end

mp.add_key_binding("ctrl+v", openURL)
