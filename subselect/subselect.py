from tkinter import *
from subliminal import *
from babelfish import Language
import sys, os
import tkinter.messagebox
import json

class subselect :

    def __init__(self) :
        self.root = Tk()
        frame = self.root
        frame.title("Subtitle Downloader")
        self.video_title_in = Entry(frame, width=100)
        self.video_title_in.bind("<Return>", self.search_)
        self.video_title_in.insert(0, videotitle)
        self.video_title_in.grid(row=0, column=0)
        self.video_title_in.focus()
        self.search_button = Button(frame, text="Search", command=self.search)
        self.search_button.grid(row=0, column=1)
        self.best_button = Button(frame, text="Best", command=self.download_best_subtitle)
        self.best_button.grid(row=0, column=2, sticky=E+W)
        self.result_listbox = Listbox(self.root)

    def show_subtitles(self, subtitles) :
        self.result_listbox.delete(0, END)
        self.subtitles_in_list = []
        for s in subtitles :
            listname = ""
            if s.provider_name == "opensubtitles" :
                listname = "[opensubtitles]: {}".format(s.filename)
            elif (s.provider_name == "podnapisi"
                    or s.provider_name == "addic7ed"
                    or s.provider_name == "subscenter") :
                listname = "[{}]: {}".format(s.provider_name, s.title)
            elif s.provider_name == "legendastv" :
                listname = "[legendastv]: {}".format(s.name)
            elif s.provider_name == "tvsubtitles" :
                listname = "[tvsubtitles]: {}".format(s.release)
            else :
                listname = "[{}]: {}".format(s.provider_name, s.id)

            self.result_listbox.insert(END, listname)
            self.subtitles_in_list += [s]
        self.result_listbox.grid(row=1, column=0, columnspan=3, sticky=E+W)

        if not hasattr(self, "download_button") :
            self.info_label = Label(self.root)
            self.info_label.grid(row=2, column=0)
            self.download_button = Button(self.root, text="Download", command=self.download_selected_subtitle)
            self.download_button.grid(row=2, column=2)
        self.info_label.configure(text="{} Subtitles".format(self.result_listbox.size()))
            
    def get_video_from_title(self) :
        video_title = self.video_title_in.get()
        self.language = sub_language
        if ";" in video_title :
            video_title = video_title.split(";")
            self.language = video_title[-1].strip()
            video_title = video_title[0]
        return Video.fromname(video_title)

    def search_(self, *args):
        self.search()

    def search(self) :
        try :
            self.video = self.get_video_from_title()
            subtitles = list_subtitles([self.video], {Language(self.language)}, providers=None, provider_configs=providers_auth)
        except ValueError as exc :
            self.show_message("Error", str(exc))
        else :
            self.show_subtitles(subtitles[self.video])

    def download_best_subtitle(self) :
        try :
            self.video = self.get_video_from_title()
            best_subtitles = download_best_subtitles([self.video], {Language(self.language)}, provider_configs=providers_auth)
        except ValueError as exc :
            self.show_message("Error", str(exc))
        else :
            if best_subtitles[self.video] != [] :
                best_subtitle = best_subtitles[self.video][0]
                self.save_subtitle(self.video, False, best_subtitle)
            else :
                self.show_message("Not found", "No subtitles found. Try a different name.")

    def download_selected_subtitle(self) :
        i = self.result_listbox.curselection()
        if i == () :
            self.show_message("Download failed", "Please select a subtitle")
        else :
            selected_subtitle = self.subtitles_in_list[i[0]]
            download_subtitles([selected_subtitle], provider_configs=providers_auth)
            self.save_subtitle(self.video, True, selected_subtitle)
    
    def save_subtitle(self, video, change_filename, subtitle) :
        if change_filename and subtitle.provider_name == "opensubtitles" :
            video.name = subtitle.filename
            title = os.path.splitext(subtitle.filename)[0]+".srt"
        else :
            title = video.name + ".srt"
        s = save_subtitles(video, [subtitle], True, save_dir)
        if s != [] :
            sys.stdout.buffer.write(title.encode("utf-8"))
            self.root.destroy()
        else :
            self.show_message("Download failed", "Subtitle download failed!")

    def show_message(self, title, msg) :
        tkinter.messagebox.showinfo(title, msg)

videotitle = save_dir = ""
sub_language = "eng"
providers_auth = {}

if len(sys.argv) > 1 :
    videotitle = sys.argv[1]
    save_dir = sys.argv[2]
    sub_language = sys.argv[3]
    providers_auth = json.loads(sys.argv[4])
    
subselect().root.mainloop()
