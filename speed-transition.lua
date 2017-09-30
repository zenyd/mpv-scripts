lookahead = 5
speedup = 2.5
leadin = 1
---------------

normalspeed=mp.get_property_native("speed")

function set_timeout()
   if mp.get_property_native("cache-size") ~= nil then
      time_out = mp.get_property_native("cache-secs")
   else
      time_out = mp.get_property_native("demuxer-readahead-secs")
   end
   return time_out
end

function restore_normalspeed()
   mp.set_property("speed", normalspeed)
   if mp.get_property_native("video-sync") == "desync" then
      mp.set_property("video-sync", "audio")
   end
end

function check_should_speedup()
   local subdelay = mp.get_property_native("sub-delay")
   mp.command("no-osd set sub-visibility no")
   mp.command("no-osd sub-step 1")
   local mark = mp.get_property("time-pos")
   local nextsubdelay = mp.get_property_native("sub-delay")
   local nextsub = subdelay - nextsubdelay
   mp.set_property("sub-delay", subdelay)
   mp.command("no-osd set sub-visibility yes")
   return nextsub, nextsub >= lookahead or nextsub == 0, mark
end

function check_position(_, position)
   if position then
      if nextsub ~= 0 and position >= (mark+nextsub-leadin) then
         restore_normalspeed()
         mp.unobserve_property(check_position)
      elseif nextsub == 0 and position >= (mark+set_timeout()-leadin) then
         nextsub, _ , mark = check_should_speedup()
      end
   end
end

function speed_transition(_, sub)
   if state == 0 then
      if sub == "" then
         nextsub, shouldspeedup, mark = check_should_speedup()
         if shouldspeedup then
            normalspeed = mp.get_property("speed")
            if mp.get_property_native("video-sync") == "audio" then
               mp.set_property("video-sync", "desync")
            end
            mp.set_property("speed", speedup)
            mp.observe_property("time-pos", "native", check_position)
            state = 1
         end
      end
   elseif state == 1 then
      if sub ~= "" and sub ~= nil or not mp.get_property_native("sid") then
         mp.unobserve_property(check_position)
         restore_normalspeed()
         state = 0
      end
   end
end

toggle2 = false

function toggle_sub_visibility()
   if not toggle2 then
      sub_color = mp.get_property("sub-color", "1/1/1/1")
      sub_color2 = mp.get_property("sub-border-color", "0/0/0/1")
      mp.set_property("sub-color", "0/0/0/0")
      mp.set_property("sub-border-color", "0/0/0/0")
   else
      mp.set_property("sub-color", sub_color)
      mp.set_property("sub-border-color", sub_color2)
   end
   mp.osd_message("subtitle visibility: "..tostring(toggle2))
   toggle2 = not toggle2
end

function change_speedup(v)
   speedup = speedup + v
   mp.osd_message("speedup: "..speedup)
end

function change_leadin(v)
   leadin = leadin + v
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

mp.add_key_binding("ctrl+j", "toggle_speedtrans", toggle)
mp.add_key_binding("alt+j", "toggle_sub_visibility", toggle_sub_visibility)
mp.add_key_binding("alt++", "increase_speedup", function() change_speedup(0.1) end)
mp.add_key_binding("alt+-", "decrease_speedup", function() change_speedup(-0.1) end)
mp.add_key_binding("alt+0", "increase_leadin", function() change_leadin(0.25) end)
mp.add_key_binding("alt+9", "decrease_leadin", function() change_leadin(-0.25) end)
