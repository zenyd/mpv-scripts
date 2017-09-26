lookahead=5  --if nextsub >= lookahead then speedup
normalspeed=mp.get_property_native("speed")
speedup=2.5
leadin=1
-------------------

state=0
enable=false

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
   subdelay = mp.get_property_native("sub-delay")
   mp.command("no-osd set sub-visibility no")
   mp.command("no-osd sub-step 1")
   nextsubdelay = mp.get_property_native("sub-delay")
   nextsub = subdelay - nextsubdelay
   --print("nextsub in seconds "..nextsub)
   mp.set_property("sub-delay", subdelay)
   mp.command("no-osd set sub-visibility yes")
   return nextsub, nextsub >= lookahead or nextsub == 0
end

function search_next_sub()
   nextsub, _ = check_should_speedup()
   add_timers(nextsub)
end

function add_timers(nextsub)
   --We know when the next sub comes
   if nextsub ~= 0 then
      --make sure we reset the speed on the unlikely case when a timer fires
      --within one second of the next sub
      if nextsub - leadin > 0 then
         mp.add_timeout((nextsub-leadin)/speedup, reset_early)
      else
         restore_normalspeed()
      end
      --We don't know when the next sub comes, so search for it recursively
   elseif nextsub == 0 then
      --search for next sub after time_out seconds, when its position might be known
      if not mp.get_property_native("pause") and set_timeout() - leadin > 0 then
         mp.add_timeout((time_out-leadin)/speedup, search_next_sub)
      end
   end
end

--reset to normal speed before subtitle shows up
--prevents ugly audio glitches when speech starts
function reset_early()
   --check if it really is time to reset
   --prevents premature change to normal speed due to seeking/pausing
   --seeking/pausing results in firing timers early/late
   if mp.get_property_native("sub-text") == "" and state == 1 then
      nextsub , shouldspeedup = check_should_speedup()
      if not shouldspeedup then
         --print("reset_early executed")
         restore_normalspeed()
      else
         --print("reset_early aborted! Seeking/Pausing?")
      end
   end
end

function speed_transition(subtext, sub)
   if state == 0 then
      if sub == "" then
         nextsub, shouldspeedup = check_should_speedup()
         if shouldspeedup then
            if mp.get_property_native("video-sync") == "audio" then
               mp.set_property("video-sync", "desync")
            end
            normalspeed = mp.get_property_native("speed")
            mp.set_property("speed", speedup)
            add_timers(nextsub)
            state = 1
         end
      end
   elseif state == 1 then
      if sub ~= "" then
         restore_normalspeed()
         state = 0
      end
   end
end

function toggle()
   if not enable then
      mp.observe_property("sub-text", "native", speed_transition)
      mp.osd_message("speed-transition enabled")
   else
      restore_normalspeed()
      mp.unobserve_property(speed_transition)
      mp.osd_message("speed-transition disabled")
   end
   state = 0
   enable = not enable
end

function pause(e,v)
   if not v and state == 1 then
      search_next_sub()
   end
end


local sub_color
local sub_color2
toggle2 = false

function toggle_sub_visibility()
   if not toggle2 then
      sub_color = mp.get_property("sub-color", "1/1/1")
      sub_color2 = mp.get_property("sub-border-color", "0/0/0")
      mp.set_property("sub-color", "0/0/0/0")
      mp.set_property("sub-border-color", "0/0/0/0")
   else
      mp.set_property("sub-color", sub_color)
      mp.set_property("sub-border-color", sub_color2)
   end
   toggle2 = not toggle2
end

function change_speedup(v)
   speedup = speedup + v
   mp.osd_message("speedup: "..speedup)
end

mp.observe_property("pause", "native", pause)
mp.add_key_binding("ctrl+j", "toggle_speedtrans", toggle)
mp.add_key_binding("alt+j", "toggle_sub_visibility", toggle_sub_visibility)
mp.add_key_binding("alt++", "increase_speedup", function() change_speedup(0.1) end)
mp.add_key_binding("alt+-", "decrease_speedup", function() change_speedup(-0.1) end)
