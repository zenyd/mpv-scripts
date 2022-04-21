local utils = require "mp.utils"

require 'mp.options'

options = {}
options.MoveToFolder = false

if package.config:sub(1,1) == "/" then
   options.DeletedFilesPath = utils.join_path(os.getenv("HOME"), "delete_file")
   ops = "unix"
else
   options.DeletedFilesPath = utils.join_path(os.getenv("USERPROFILE"), "delete_file")
   ops = "win"
end

read_options(options)


del_list = {}

function createDirectory()
   if not utils.file_info(options.DeletedFilesPath) then
      if not os.execute(string.format('mkdir "%s"', options.DeletedFilesPath)) then
         print("failed to create folder")
      end
   end
end

function contains_item(l, i)
   for k, v in pairs(l) do
      if v == i then
         mp.osd_message("undeleting current file")
         l[k] = nil
         return true
      end
   end
   mp.osd_message("deleting current file")
   return false
end

function mark_delete()
   local work_dir = mp.get_property_native("working-directory")
   local file_path = mp.get_property_native("path")
   local s = file_path:find(work_dir, 0, true)
   local final_path
   if s and s == 0 then
      final_path = file_path
   else
      final_path = utils.join_path(work_dir, file_path)
   end
   if not contains_item(del_list, final_path) then
      table.insert(del_list, final_path)
   end
end

function delete()
   if options.MoveToFolder then
      --create folder if not exists
      createDirectory()
   end

   for i, v in pairs(del_list) do
      if options.MoveToFolder then
         print("moving: "..v)
         local _, file_name = utils.split_path(v)
         --this loop will add a number to the file name if it already exists in the directory
         --But limit the number of iterations
         for i = 1,100 do
            if i > 1 then
               if file_name:find("[.].+$") then
                  file_name = file_name:gsub("([.].+)$", string.format("_%d%%1", i))
               else
                  file_name = string.format("%s_%d", file_name, i)
               end
            end
            
            local movedPath = utils.join_path(options.DeletedFilesPath, file_name)
            local fileInfo = utils.file_info(movedPath)
            if not fileInfo then
               os.rename(v, movedPath)
               break
            end
         end
      else
         print("deleting: "..v)
         os.remove(v)
      end
   end
end

function showList()
   local delString = "Delete Marks:\n"
   for _,v in pairs(del_list) do
      local dFile = v:gsub("/","\\")
      delString = delString..dFile:match("\\*([^\\]*)$").."; "
   end
   if delString:find(";") then
      mp.osd_message(delString)
      return delString
   elseif showListTimer then
      showListTimer:kill()
   end
end
showListTimer = mp.add_periodic_timer(1,showList)
showListTimer:kill()
function list_marks()
   if showListTimer:is_enabled() then
      showListTimer:kill()
      mp.osd_message("",0)
   else
      local delString = showList()
      if delString and delString:find(";") then
         showListTimer:resume()
         print(delString)
      else
         showListTimer:kill()
      end
   end
end

mp.add_key_binding("ctrl+DEL", "delete_file", mark_delete)
mp.add_key_binding("alt+DEL", "list_marks", list_marks)
mp.add_key_binding("ctrl+shift+DEL", "clear_list", function() mp.osd_message("Undelete all"); del_list = {}; end)
mp.register_event("shutdown", delete)
