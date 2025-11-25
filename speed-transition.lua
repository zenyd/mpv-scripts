local opt = require 'mp.options'
local msg = require 'mp.msg'

cfg = {
	lookahead = 5,            --if the next subtitle appears after this threshold then speedup
	speedup = 2,              --the value that 'speed' is set to during speedup
	leadin = 1,               --seconds to stop short of the next subtitle
	sub_timeout = 5,          --if a subtitle is visible for longer than this value, speedup begins; set to 0 to disable
	skipmode = false,         --instead of speeding up playback seek to the next known subtitle
	maxSkip = 2.5,            --max skip distance (seconds) when skipmode is enabled
	minSkip = 1,              --this is also configurable but setting it too low can actually make your watch time longer
	skipdelay = 0.8,          --in skip mode, this setting delays each skip by x seconds (must be >=0)
	directskip = false,       --seek to next known subtitle (must be in cache) no matter how far away
	exact_skip = true,        --use accurate but slow skips
	--Because mpv syncs subtitles to audio it is possible that if audio processing lags behind--
	--video processing then normal playback may not resume in sync with the video. If 'avsync' > leadin--
	--then this disables the audio so that we can ensure normal playback resumes on time.
	dropOnAVdesync = true,
	ignorePattern = false,    --if true, subtitles are matched against 'subPattern'. A successful match will be treated as if there was no subtitle
	subPattern = '^[#♯♩♪♬♫🎵🎶%[%(]+.*[#♯♩♪♬♫🎵🎶%]%)]+$'
}

opt.read_options(cfg)

readahead_secs = mp.get_property_native('demuxer-readahead-secs')
normalspeed = mp.get_property_native('speed')

enable = false
state = 0
firstskip = true --make the first skip in skip mode not have to wait for skipdelay
aid = nil

--defines how far away we need to be at least from the end of the subtitle to not consider skipping back
--since we don't always know for how long the subtitle is displayed this is just an arbitrary number
SKIP_BACK_WINDOW = 1 --only applies for tSkip <= 3

function shouldIgnore(subtext)
	if cfg.ignorePattern and subtext and subtext ~= '' then
		local st = subtext:match('^%s*(.-)%s*$') -- trim whitespace
		if st:find(cfg.subPattern) then
			return true
		end
	else
		return false
	end
end

function clamp(v, l, u)
	if l and v < l then
		v = l
	elseif u and v > u then
		v = u
	end
	return v
end

function formatTime(s)
	if not s then
		return nil
	end

	s = math.abs(s)
	local _s = s % 60
	s = s / 60
	local m = math.floor(s % 60)
	s = s / 60
	local h = math.floor(s)
	return string.format('%02d:%02d:%02f', h, m, _s)
end

function sleep(s)
	local ntime = os.clock() + s
	repeat until os.clock() > ntime
end

function reset_state()
	nextsub, shouldspeedup, speedup_zone_begin, speedup_zone_end = nil, false, nil, nil
	last_speedup_zone_begin = nil
	last_skip_position = nil
	last_nextsub_check = nil
	firstskip = true
	state = 0
end

function restore_normalspeed()
	if not cfg.skipmode then
		mp.set_property('speed', normalspeed)
		if video_sync then
			mp.set_property('video-sync', video_sync)
		end
	end
	if aid and aid ~= mp.get_property('aid') then
		mp.set_property('aid', aid)
	end
end

function speed_up()
	normalspeed = mp.get_property('speed')
	video_sync = mp.get_property('video-sync')
	mp.set_property('video-sync', 'desync')
	mp.set_property('speed', cfg.speedup)
	if cfg.dropOnAVdesync then
		aid = mp.get_property('aid')
		mp.observe_property('avsync', 'native', check_audio)
	end
end

function skip(skipval)
	if skipval < cfg.minSkip then
		msg.warn('skip(): tskip < minSkip; abort!')
		return
	end
	if cfg.exact_skip then
		mp.commandv('seek', skipval, 'relative', 'exact')
	else
		mp.commandv('seek', skipval, 'relative')
	end
end

function delayskip(position, skipdelay)
	if not (firstskip or skipdelay == 0) then
		sleep(skipdelay)
		local tposition = mp.get_property_number('time-pos')
		if not tposition then
			position = position + skipdelay
		else
			position = tposition
		end
	end

	firstskip = false
	return position
end

function skipval(nextsub)
	local demuxer_cache_duration = mp.get_property_number('demuxer-cache-duration', 0)
	msg.trace('skipval()')
	msg.trace('  demuxer_cache_duration:', demuxer_cache_duration)
	msg.trace('  nextsub:', nextsub)
	local skipval = demuxer_cache_duration * 0.8
	if skipval == 0 or nextsub == 0 then
		skipval = cfg.maxSkip
	end

	if nextsub > 0 then
		if cfg.directskip then
			skipval = clamp(nextsub - cfg.leadin, 0, nil)
		elseif nextsub - cfg.leadin <= skipval then
			skipval = clamp(nextsub - cfg.leadin, 0, skipval)
		else
			skipval = clamp(skipval, 0, clamp(skipval, 0, clamp(nextsub - cfg.leadin, 0, cfg.maxSkip)))
		end
	end

	if skipval < cfg.minSkip then
		skipval = 0
	elseif skipval > cfg.maxSkip and not cfg.directskip then
		skipval = cfg.maxSkip
	end

	msg.trace('  skipval:', skipval)

	return skipval, skipval >= cfg.minSkip
end

function wait_finish_seeking()
	repeat
		local seeking = mp.get_property_bool('seeking')
	until not seeking
end

function skip_back_if_needed(position, subend)
	msg.debug('  skip_back()')
	if not last_skip_position then
		msg.debug('    last_skip_position undefined')
		reset_state()
		return
	end

	msg.debug('    position:', formatTime(position))
	msg.debug('    subend:', formatTime(subend))
	local skipback_position = last_skip_position
	local tskip = position - last_skip_position
	msg.debug('    tskip:', tskip)
	msg.debug('    subend - position:', subend - position)

	if tskip <= 3 then
		if subend - position >= SKIP_BACK_WINDOW then
			msg.debug('    ->within margin - interrupt skip back')
			reset_state()
			return
		end
	end
	msg.debug('    ->skip back to:', formatTime(skipback_position))
	-- wait_finish_seeking()
	mp.set_property_number('time-pos', skipback_position)
	reset_state()
end

function check_audio(_, ds)
	if not ds or cfg.skipmode or state == 0 or cfg.leadin == 0 then
		return
	elseif (state == 1 or state == 3) and tonumber(ds) > cfg.leadin and mp.get_property('aid') ~= 'no' then
		aid = mp.get_property('aid')
		mp.set_property('aid', 'no')
		msg.warn('avsync greater than leadin, dropping audio')
	end
end

function check_should_speedup(subend)
	local subspeed = mp.get_property_number('sub-speed', 1)
	local subdelay = mp.get_property_number('sub-delay')
	local substart = mp.get_property_number('sub-start')

	subend = subend * subspeed + subdelay

	if substart then
		substart = substart * subspeed + subdelay
	end

	if cfg.sub_timeout > 0 and substart and substart < subend then
		if subend - substart >= cfg.sub_timeout then
			subend = substart + cfg.sub_timeout
		end
	end

	local sub_visibility = mp.get_property_bool('sub-visibility')
	if sub_visibility then
		mp.set_property_bool('sub-visibility', false)
	end

	mp.commandv('sub-step', 1)

	local nextsubstart = mp.get_property_number('sub-start')
	if nextsubstart then
		nextsubstart = nextsubstart * subspeed + subdelay
	end

	if cfg.ignorePattern and nextsubstart and subend < nextsubstart then
		repeat
			local ignore = shouldIgnore(mp.get_property('sub-text'))
			if ignore then
				local t_nextsubstart = mp.get_property_number('sub-end')
				if t_nextsubstart then
					t_nextsubstart = t_nextsubstart * subspeed + subdelay
				end
				if t_nextsubstart and t_nextsubstart > nextsubstart then
					nextsubstart = t_nextsubstart
					mp.commandv('sub-step', 1)
				else
					break
				end
			end
		until not ignore
	end

	mp.set_property_number('sub-delay', subdelay)
	if sub_visibility then
		mp.set_property_bool('sub-visibility', true)
	end

	msg.trace('s-start,s-end,ns-start:', formatTime(substart), formatTime(subend), formatTime(nextsubstart))

	local nextsub
	if nextsubstart then
		if subend < nextsubstart then
			nextsub = nextsubstart - subend
		end
	end

	if cfg.leadin > cfg.lookahead then
		cfg.leadin = 0
	end

	local shouldspeedup = nextsub and nextsub >= cfg.lookahead - cfg.leadin
	local speedup_begin = subend
	if shouldspeedup then
		msg.debug('check_should_speedup()')
		msg.debug('  shouldspeedup:', tostring(shouldspeedup))
		msg.debug('  speedup_begin:', formatTime(speedup_begin) or '')
		msg.debug('  nextsub:', nextsub or '')
	end

	return nextsub, shouldspeedup, speedup_begin
end

function check_position(_, position)
	if position then
		if state == 0 and speedup_zone_begin and position >= speedup_zone_begin and shouldspeedup then
			if cfg.skipmode then
				msg.debug('check_position[0] -> [2]')
				msg.debug('  position:', formatTime(position))
				firstskip = true
				state = 2
			else
				msg.debug('check_position[0] -> [1]')
				msg.debug('  position:', formatTime(position))
				speed_up()
				state = 1
			end

			msg.debug('  speedup_zone_begin:', formatTime(speedup_zone_begin))
			msg.debug('  speedup_zone_end:', formatTime(speedup_zone_end))
		elseif state == 0 and not nextsub and last_speedup_zone_begin and position - last_speedup_zone_begin > 2 then
			msg.debug('check_position[0] -> [3]')
			msg.debug('  position:', formatTime(position))
			if not cfg.skipmode then
				speed_up()
			end
			last_speedup_zone_begin = nil
			last_nextsub_check = position
			speedup_zone_begin = position
			speedup_zone_end = nil
			firstskip = true
			state = 3
		elseif state == 1 and speedup_zone_end and position >= speedup_zone_end then
			restore_normalspeed()
			reset_state()
			msg.debug('check_position[1] -> [0]')
			msg.debug('  position:', formatTime(position))
		elseif state == 2 then
			-- 			msg.debug('check_position[2]')
			-- 			msg.debug('  position:', formatTime(position))
			if speedup_zone_end and position >= speedup_zone_end then
				msg.debug('check_position[2] -> [0] pos >= end')
				msg.debug('  position:', formatTime(position))
				msg.debug('  speedup_zone_end:', formatTime(speedup_zone_end))
				if not cfg.exact_skip and last_skip_position and position > speedup_zone_end then
					if position > speedup_zone_end + cfg.leadin then
						msg.debug('  ->seek back to:', formatTime(last_skip_position))
						-- wait_finish_seeking()
						mp.set_property_number('time-pos', last_skip_position)
					else
						msg.debug('  ->within margin - interrupt skip back')
					end
				end
				reset_state()
			elseif speedup_zone_begin <= position and position < speedup_zone_end then
				if mp.get_property('pause') == 'no' then
					local position_after_skipdelay = position
					wait_finish_seeking()
					if position + cfg.skipdelay < speedup_zone_end then
						position_after_skipdelay = delayskip(position, cfg.skipdelay)
					end
					local nextsub_start = speedup_zone_end + cfg.leadin - position_after_skipdelay
					local tSkip, can_skip = skipval(nextsub_start)
					if nextsub_start > 0 and can_skip then
						if position_after_skipdelay + tSkip >= speedup_zone_end then
							if speedup_zone_end + cfg.leadin - position_after_skipdelay >= cfg.minSkip then
								wait_finish_seeking()
								mp.set_property_number('time-pos', speedup_zone_end + cfg.leadin)
								msg.debug('check_position[2]')
								msg.debug('  position:', formatTime(position_after_skipdelay))
								msg.debug('  nextsub:', nextsub_start)
								msg.debug('  direct skip to:', formatTime(speedup_zone_end + cfg.leadin))
								reset_state()
							end
						else
							local seeking = mp.get_property_bool('seeking')
							if not seeking then
								last_skip_position = position_after_skipdelay
								skip(tSkip)
								msg.debug('check_position[2]')
								msg.debug('  position:', formatTime(position_after_skipdelay))
								msg.debug('  nextsub:', nextsub_start)
								msg.debug('  skipval:', tSkip)
							end
						end
					elseif nextsub_start < 0 and not cfg.exact_skip then
						local cursubend = mp.get_property_number('sub-end')
						local margin = 0.5
						if cursubend and cursubend > speedup_zone_end + cfg.leadin then
							margin = clamp((cursubend - (speedup_zone_end + cfg.leadin)) * 0.35, 0, 1)
						end
						if position_after_skipdelay > speedup_zone_end + cfg.leadin + margin then
							wait_finish_seeking()
							mp.set_property_number('time-pos', speedup_zone_end)
							msg.debug('check_position[2]')
							msg.debug('  position:', formatTime(position_after_skipdelay))
							msg.debug('  nextsub:', nextsub_start)
							msg.debug('  skipval:', tSkip)
							msg.debug('  margin:', margin)
							msg.debug('  ->seek back to: ' .. formatTime(speedup_zone_end))
						end
						reset_state()
					else
						reset_state()
					end
				end
			end
		elseif state == 3 then
			if position - last_nextsub_check > 0.5 then
				local t_nextsub, t_shouldspeedup, t_speedup_zone_begin = check_should_speedup(position)
				if t_nextsub then
					msg.debug('check_position[3]')
					msg.debug('  position:', formatTime(position))
					msg.debug('  ->found next sub')
					if not t_shouldspeedup then
						msg.debug('  ->stop speedup')
						msg.debug('  [3] -> [0]')
						restore_normalspeed()
						reset_state()
						return
					else
						nextsub, shouldspeedup = t_nextsub, t_shouldspeedup
						speedup_zone_end = t_speedup_zone_begin + nextsub - cfg.leadin

						if cfg.skipmode then
							msg.debug('check_position[3] -> [2]')
							state = 2
							return
						else
							msg.debug('check_position[3] -> [1]')
							state = 1
							last_nextsub_check = position
							return
						end
					end
				end
				last_nextsub_check = position
			end

			if cfg.skipmode then
				local seeking = mp.get_property_bool('seeking')
				if mp.get_property('pause') == 'no' and not seeking then
					local tSkip, can_skip = skipval(0)
					if can_skip then
						position = delayskip(position, cfg.skipdelay)
						last_skip_position = position
						skip(tSkip)
						msg.debug('check_position[3]')
						msg.debug('  position:', formatTime(position))
						msg.debug('  nextsub: ---')
						msg.debug('  skipval:', tSkip)
					end
				end
			end
		else

		end
	end
end

function speed_transition(_, subend)
	if not subend then
		return
	end

	msg.debug('speed_transition()')

	if state == 3 or (state == 2 and not cfg.exact_skip) then
		msg.debug('  state >= 2: check seek back / reset')
		local position = mp.get_property_number('time-pos')
		if cfg.skipmode then
			skip_back_if_needed(position, subend)
		end
		restore_normalspeed()
		reset_state()
	end

	local t_nextsub, t_shouldspeedup, t_speedup_zone_begin = check_should_speedup(subend)
	if t_shouldspeedup then
		if state ~= 0 then
			msg.debug('  ->reset: state > 0')
			restore_normalspeed()
			reset_state()
		end
		nextsub, shouldspeedup, speedup_zone_begin = t_nextsub, t_shouldspeedup, t_speedup_zone_begin
		speedup_zone_end = speedup_zone_begin + nextsub - cfg.leadin
		msg.debug('  speedup_zone_end:', formatTime(speedup_zone_end) or '')
	else
		if state ~= 0 then
			msg.debug('  ->reset: state > 0')
			restore_normalspeed()
		end
		reset_state()
	end
	last_speedup_zone_begin = t_speedup_zone_begin
end

function toggle()
	if not enable then
		normalspeed = mp.get_property('speed')
		local calculated_readaheadsecs = math.max(5, readahead_secs, cfg.maxSkip + cfg.leadin,
			cfg.lookahead + cfg.leadin)
		if readahead_secs < calculated_readaheadsecs then
			mp.set_property('demuxer-readahead-secs', calculated_readaheadsecs)
		end
		last_speedup_zone_begin = mp.get_property_number('time-pos')
		mp.observe_property('sub-end', 'number', speed_transition)
		mp.observe_property('time-pos', 'number', check_position)
		mp.osd_message('speed-transition enabled')
		msg.info('enabled')
	else
		restore_normalspeed()
		reset_state()
		mp.set_property('demuxer-readahead-secs', readahead_secs)
		mp.unobserve_property(speed_transition)
		mp.unobserve_property(check_position)
		mp.unobserve_property(check_audio)
		mp.osd_message('speed-transition disabled')
		msg.info('disabled')
	end
	state = 0
	enable = not enable
end

function switch_mode()
	cfg.skipmode = not cfg.skipmode
	if not enable then
		toggle()
	end
	if cfg.skipmode then
		if state == 1 or state == 3 then
			if state == 1 then
				state = 2
			end
			mp.set_property('speed', normalspeed)
		end
		mp.osd_message('skip mode')
		msg.info('skip mode')
	else
		if state == 2 or state == 3 then
			if state == 2 then
				state = 1
			end
			speed_up()
		end
		mp.osd_message('speed mode')
		msg.info('speed mode')
	end
end

function reset_on_file_load()
	if enable then
		restore_normalspeed()
	end
	reset_state()
end

function change_speedup(v)
	cfg.speedup = cfg.speedup + v
	if not cfg.skipmode and (state == 1 or state == 3) then
		mp.set_property('speed', cfg.speedup)
	end
	mp.osd_message('speedup: ' .. cfg.speedup)
	msg.info('speedup:', cfg.speedup)
end

function change_leadin(v)
	cfg.leadin = clamp(cfg.leadin + v, 0, 2)
	mp.osd_message('leadin: ' .. cfg.leadin)
	msg.info('leadin:', cfg.leadin)
end

function change_lookAhead(v)
	cfg.lookahead = clamp(cfg.lookahead + v, 0, nil)
	mp.osd_message('lookahead: ' .. cfg.lookahead)
	msg.info('lookahead:', cfg.lookahead)
end

mp.add_key_binding('ctrl+j', 'toggle_speedtrans', toggle)
mp.add_key_binding('alt+j', 'switch_mode', switch_mode)
mp.add_key_binding('alt++', 'increase_speedup', function() change_speedup(0.1) end, { repeatable = true })
mp.add_key_binding('alt+-', 'decrease_speedup', function() change_speedup(-0.1) end, { repeatable = true })
mp.add_key_binding('alt+0', 'increase_leadin', function() change_leadin(0.25) end)
mp.add_key_binding('alt+9', 'decrease_leadin', function() change_leadin(-0.25) end)
mp.add_key_binding('alt+8', 'increase_lookahead', function() change_lookAhead(0.25) end)
mp.add_key_binding('alt+7', 'decrease_lookahead', function() change_lookAhead(-0.25) end)
mp.register_event('file-loaded', reset_on_file_load)
