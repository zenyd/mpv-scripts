local utils = require 'mp.utils'

SkipIndex = 1
SkipWindow = nil

names_directory = utils.join_path(mp.get_script_directory(), 'names')
--read-in filenames for files to be censored
names = utils.readdir(names_directory)


--execute a skip when in skip window and set the next skip window
function skip(time_pos, tpos)
   if SkipWindow == nil or tpos == nil then return end

   if withinSkipWindow(SkipWindow, tpos) then
      local skipTo = SkipWindow[2]
      SkipIndex = SkipIndex + 1
      SkipWindow = TimeStamps[SkipIndex]
      mp.set_property_number('time-pos', skipTo)
   end
end

function withinSkipWindow(skipwindow, tpos)
   return tpos >= skipwindow[1] and tpos < skipwindow[2]
end

function isNextSkipWindow(skipwindow, tpos)
   return skipwindow[1] > tpos
end

--when seeking forward/backward we need to find the correct skip window related to current time position
function searchSkipWindow(seeking)
   SkipWindow = nil
   local curPos = mp.get_property_number('time-pos')
   if TimeStamps and curPos then
      --iterate over all our timestamps and find the correct window
      for i, window in ipairs(TimeStamps) do
         if withinSkipWindow(window, curPos) then
            SkipIndex = i
            SkipWindow = window
            break
         elseif isNextSkipWindow(window, curPos) then
            SkipIndex = i
            SkipWindow = window
            break
         end
      end
   end
end

--return timeformat in seconds
function tryParseTimeFormat(line)
   --parse line
   local h1, m1, s1, h2, m2, s2 = line:match('(%d+):(%d%d):(%d%d%.?%d*)%s+(%d+):(%d%d):(%d%d%.?%d*)')
   
   if not h1 then
      print('invalid line/time format: ' .. line)
      return nil
   end

   h1 = tonumber(h1)
   h2 = tonumber(h2)
   m1 = tonumber(m1)
   m2 = tonumber(m2)
   s1 = tonumber(s1)
   s2 = tonumber(s2)

   --check ranges for time parts
   if m1 >= 60 or m2 >= 60 or s1 >= 60 or s2 >= 60 then
      print('invalid time format - there are time parts >= 60')
      return nil
   end

   --convert into seconds
   local t1 = h1*60*60 + m1*60 + s1
   local t2 = h2*60*60 + m2*60 + s2

   return t1, t2
end

function handler()
   local filename = mp.get_property('filename/no-ext', nil)
   print('filename: ' .. filename)

   if filename ~= nil and names ~= nil then
      for _, name in ipairs(names) do
         --extract filename (containing timestamps) w/o extension
         name_ = string.gsub(name, '%.[^.]+$', '')
         if name_ == filename then
            --found a timestamp file (name stores path to file)
            TimeStamps = {}

            --parse file and get timestamps into table TimeStamps
            for line in io.lines(utils.join_path(names_directory, name)) do
               local t1, t2 = tryParseTimeFormat(line)
               if t1 ~= nil then
                  --valid timestamps found - insert into table
                  table.insert(TimeStamps, { tonumber(t1), tonumber(t2) })
               end
            end
            break
         end
      end

      if TimeStamps and #TimeStamps > 0 then
         print('TimeStamps: '..utils.to_string(TimeStamps))
         print('Active')

         mp.observe_property('seeking', nil, searchSkipWindow)
         mp.observe_property('time-pos', 'number', skip)
      end
   end
end

mp.register_event('file-loaded', handler)
