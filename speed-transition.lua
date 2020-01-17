lookahead = 5
speedup = 2.5
leadin = 1 --range 0-2
skipmode = false
directskip = false
---------------

normalspeed=mp.get_property_native("speed")

function set_timeout()
   local time_out
   if mp.get_property_native("cache-size") ~= nil then
      time_out = mp.get_property_native("cache-secs")
   else
      time_out = mp.get_property_native("demuxer-readahead-secs")
   end
   return time_out
end

local aid
function restore_normalspeed()
   mp.set_property("speed", normalspeed)
   if mp.get_property_native("video-sync") == "desync" then
      mp.set_property("video-sync", "audio")
   end
   if (aid~=nil and aid~=mp.get_property("aid")) then mp.set_property("aid", aid) end
end

function check_should_speedup()
   local subdelay = mp.get_property_native("sub-delay")
   mp.command("no-osd set sub-visibility no")
   mp.command("no-osd sub-step 1")
   local mark = mp.get_property_native("time-pos")
   local nextsubdelay = mp.get_property_native("sub-delay")
   local nextsub = subdelay - nextsubdelay
   mp.set_property("sub-delay", subdelay)
   mp.command("no-osd set sub-visibility yes")
   return nextsub, nextsub >= lookahead or nextsub == 0, mark
end

function check_audio(_,ds)
   if state==0 then
      return
   end
   if ds and tonumber(ds)>leadin then
      aid = mp.get_property("aid")
      mp.set_property("aid", "no")
      print("avsync greater than leadin, dropping audio")
   end
end

function check_position(_, position)
   if position then
      if nextsub ~= 0 and position >= (mark+nextsub-leadin) then
         restore_normalspeed()
         mp.unobserve_property(check_position)
         mp.unobserve_property(check_audio)
      elseif nextsub == 0 and position >= (mark+set_timeout()-leadin) then
         nextsub, _ , mark = check_should_speedup()
      end
   end
end

function skipval()
   local skipval = mp.get_property_native("demuxer-cache-duration", 5)
   skipval = clamp(skipval, 1, 5)
   if nextsub > 0 then
      if nextsub-skipval-leadin <= 0 or directskip then
         skipval = nextsub - leadin
      end
   else
      skipval = clamp(skipval-leadin, 0, nil)
      if skipval == 0 then
         skipval = clamp(skipval-1, 1, nil)
      end
   end
   return skipval
end

function speed_transition(_, sub)
   if state == 0 then
      if sub == "" then
         last_speedup_zone_begin = speedup_zone_begin
         nextsub, shouldspeedup, speedup_zone_begin = check_should_speedup()
         mark = speedup_zone_begin
         speedup_zone_end = mark+nextsub
         if shouldspeedup then
            local temp_disable_skipmode = false
            if last_speedup_zone_begin and mark < last_speedup_zone_begin then
               temp_disable_skipmode = true
            end
            if skipmode and not temp_disable_skipmode and mp.get_property("pause") == "no" then
               mp.commandv("no-osd", "seek", skipval(), "relative", "exact")
            else
               normalspeed = mp.get_property("speed")
               if mp.get_property_native("video-sync") == "audio" then
                  mp.set_property("video-sync", "desync")
               end
               mp.set_property("speed", speedup)
               mp.observe_property("time-pos", "native", check_position)
               state = 1
               aid=mp.get_property("aid")
               mp.observe_property("avsync", "native", check_audio)
            end
         end
      end
   elseif state == 1 then
      if sub ~= "" and sub ~= nil or not mp.get_property_native("sid") then
         mp.unobserve_property(check_position)
         mp.unobserve_property(check_audio)
         restore_normalspeed()
         state = 0
      else
         local pos = mp.get_property_native("time-pos", 0)
         if pos < speedup_zone_begin or pos > speedup_zone_end then
            nextsub, _ , mark = check_should_speedup()
         end
      end
   end
end

toggle2 = false

function toggle_sub_visibility()
   if not toggle2 then
      sub_color = mp.get_property("sub-color", "1/1/1/1")
      sub_color2 = mp.get_property("sub-border-color", "0/0/0/1")
      sub_color3 = mp.get_property("sub-shadow-color", "0/0/0/1")
      mp.set_property("sub-color", "0/0/0/0")
      mp.set_property("sub-border-color", "0/0/0/0")
      mp.set_property("sub-shadow-color", "0/0/0/0")
   else
      mp.set_property("sub-color", sub_color)
      mp.set_property("sub-border-color", sub_color2)
      mp.set_property("sub-shadow-color", sub_color3)
   end
   mp.osd_message("subtitle visibility: "..tostring(toggle2))
   toggle2 = not toggle2
end

function toggle_skipmode()
   skipmode = not skipmode
   if enable then
      toggle()
      toggle()
   end
   if skipmode then
      mp.osd_message("skip mode")
   else
      mp.osd_message("speed mode")
   end
end

function clamp(v,l,u)
   if l and v < l then
      v = l
   elseif u and v > u then
      v = u
   end
   return v
end

function change_speedup(v)
   speedup = speedup + v
   mp.osd_message("speedup: "..speedup)
end

function change_leadin(v)
   leadin = clamp(leadin + v, 0, 2)
   mp.osd_message("leadin: "..leadin)
end

enable = false
state = 0

function toggle()
   if not enable then
      normalspeed = mp.get_property("speed")
      mp.observe_property("sub-text", "native", speed_transition)
      mp.osd_message("speed-transition enabled")
   else
      restore_normalspeed()
      mp.unobserve_property(speed_transition)
      mp.unobserve_property(check_position)
      mp.osd_message("speed-transition disabled")
   end
   state = 0
   enable = not enable
end

function reset_on_file_load()
   if state == 1 then
      mp.unobserve_property(check_position)
      restore_normalspeed()
      state = 0
   end
end

mp.add_key_binding("ctrl+j", "toggle_speedtrans", toggle)
mp.add_key_binding("alt+j", "toggle_sub_visibility", toggle_sub_visibility)
mp.add_key_binding("ctrl+alt+j", "toggle_skipmode", toggle_skipmode)
mp.add_key_binding("alt++", "increase_speedup", function() change_speedup(0.1) end)
mp.add_key_binding("alt+-", "decrease_speedup", function() change_speedup(-0.1) end)
mp.add_key_binding("alt+0", "increase_leadin", function() change_leadin(0.25) end)
mp.add_key_binding("alt+9", "decrease_leadin", function() change_leadin(-0.25) end)
mp.register_event("file-loaded", reset_on_file_load)
