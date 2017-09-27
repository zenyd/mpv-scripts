local leadin = 1
local lookahead = 5
local speedup=6
---------------

local normalspeed=1
function restore_normalspeed()
   mp.set_property("speed", normalspeed)
   if mp.get_property_native("video-sync") == "desync" then
      mp.set_property("video-sync", "audio")
   end
end

local mark = 0
function check_should_speedup()
   subdelay = mp.get_property_native("sub-delay")
   mp.command("no-osd set sub-visibility no")
   mp.command("no-osd sub-step 1")
   mark = mp.get_property("time-pos")
   nextsubdelay = mp.get_property_native("sub-delay")
   nextsub = subdelay - nextsubdelay
   mp.set_property("sub-delay", subdelay)
   mp.command("no-osd set sub-visibility yes")
   return nextsub
end

local searching = false
function postioncheck(_,position)
   if position then
      if nextsub~=0 and position>=(mark+nextsub-leadin) then
         restore_normalspeed()
         mp.unobserve_property(postioncheck)
         searching = false
      else
         check_should_speedup()
      end
   end
end

function speed_transition(_,text)
   if text=="" then
      local next1 = check_should_speedup()
      if (next1 > leadin and next1 >= lookahead) or next1==0 then
         if searching == false then
            normalspeed = mp.get_property("speed")
            if mp.get_property_native("video-sync") == "audio" then
               mp.set_property("video-sync", "desync")
            end
         end
         searching = true
         mp.set_property("speed", speedup)
         mark = mp.get_property("time-pos")
         mp.observe_property("time-pos", "native", postioncheck)
      end
   end
end

local sub_color
local sub_color2
local toggle2 = true
function toggle_sub_visibility()
   if toggle2==true then
      sub_color = mp.get_property("sub-color", "1/1/1/1")
      sub_color2 = mp.get_property("sub-border-color", "0/0/0/1")
      mp.set_property("sub-color", "0/0/0/0")
      mp.set_property("sub-border-color", "0/0/0/0")
   else
      mp.set_property("sub-color", sub_color)
      mp.set_property("sub-border-color", sub_color2)
   end
   toggle2 = not toggle2
    mp.osd_message("subtitle visibility: "..tostring(toggle2))
end

function change_speedup(v)
   speedup = speedup + v
   mp.osd_message("speedup: "..speedup)
end

function change_leadin(v)
   leadin = leadin + v
   mp.osd_message("leadin: "..leadin)
end

local enable = false
function toggle()
   if not enable then
      mp.observe_property("sub-text", "native", speed_transition)
      mp.osd_message("speed-transition enabled")
   else
      restore_normalspeed()
      mp.unobserve_property(speed_transition)
      mp.osd_message("speed-transition disabled")
   end
   enable = not enable
end

mp.add_key_binding("ctrl+j", "toggle_speedtrans", toggle)
mp.add_key_binding("alt+j", "toggle_sub_visibility", toggle_sub_visibility)
mp.add_key_binding("alt++", "increase_speedup", function() change_speedup(0.1) end)
mp.add_key_binding("alt+-", "decrease_speedup", function() change_speedup(-0.1) end)
mp.add_key_binding("alt+0", "increase_leadin", function() change_leadin(0.25) end)
mp.add_key_binding("alt+9", "decrease_leadin", function() change_leadin(-0.25) end)
