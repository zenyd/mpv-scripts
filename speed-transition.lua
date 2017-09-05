lookahead=5  --if nextsub >= lookahead then speedup
normalspeed=mp.get_property_native("speed")
speedup=2.5
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

function check_should_speedup()
   subdelay = mp.get_property_native("sub-delay")
   mp.command("no-osd set sub-visibility no")
   mp.command("no-osd sub-step 1")
   nextsub = math.abs(mp.get_property_native("sub-delay"))-math.abs(subdelay)
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
      if nextsub - 1 > 0 then
         mp.add_timeout((nextsub-1)/speedup, reset_early)
      else
         mp.set_property("speed", normalspeed)
      end
      --We don't know when the next sub comes, so search for it recursively
   elseif nextsub == 0 then
      --search for next sub after time_out seconds, when its position might be known
      if not mp.get_property_native("pause") and set_timeout() - 1 > 0 then
         mp.add_timeout((time_out-1)/speedup, search_next_sub)
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
         mp.set_property("speed", normalspeed)
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
            normalspeed = mp.get_property_native("speed")
            mp.set_property("speed", speedup)
            add_timers(nextsub)
            state = 1
         end
      end
   elseif state == 1 then
      if sub ~= "" then
         mp.set_property("speed", normalspeed)
         state = 0
      end
   end
end

function toggle()
   if not enable then
      enable = true
      state = 0
      mp.observe_property("sub-text", "native", speed_transition)
      mp.osd_message("speed-transition enabled")
   else
      enable = false
      state = 0
      mp.set_property("speed", normalspeed)
      mp.unobserve_property(speed_transition)
      mp.osd_message("speed-transition disabled")
   end
end

function pause(e,v)
   if not v and state == 1 then
      search_next_sub()
   end
end

mp.observe_property("pause", "native", pause)
mp.add_key_binding("Ctrl+j", "toggle_speedtrans", toggle)
