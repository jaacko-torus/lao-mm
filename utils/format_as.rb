$format_as = {
	:VAR => {
		:max_tot__length => 0,
		:max_volume__length => 0,
		:max_page__length => 0,
		:max_line__length => 0,
		:max_char__length => 0,
		:character__soft_limit_length => 0
	},
	per_pad_w_space: -> (per) { "%6.2f" % per },
	per_pad_w_0: -> (per) { "%06.2f" % per },
	at_length_w_space: -> (value, length) { "%#{length}i" % value },
	at_length_w_0: -> (value, length) { "%0#{length}i" % value },
	at_full_length: -> (value) { $format_as[:at_length_w_space].(value, $format_as[:VAR][:max_tot__length]) },
	
	line_stat_compact: -> (code, cur, tot, per, length) do
		cur = $format_as[:at_length_w_0].(cur, length)
		tot = $format_as[:at_length_w_0].(tot, length)
		per = $format_as[:per_pad_w_0].(per)
		return "#{code}:#{cur}/#{tot}@#{per}%"
	end,
	
	stat_compact: -> (stats) do
		stats = stats.map { |stat_code, stat_values|
			length = $format_as[:VAR]["max_#{
				{ :v => "volume", :p => "page", :l => "line", :c => "char" }[stat_code]
			}__length".to_sym]
			[stat_code, $format_as[:line_stat_compact].(
				stat_code,
				stat_values[:cur],
				stat_values[:tot],
				stat_values[:per],
				length
			)]
		}.to_h
		
		return "#{stats[:v]}#{stats[:p]}#{stats[:l]}#{stats[:c]}"
	end,
	
	stat_full: -> (code, cur, tot, per) do
		codes = %w[volume page line char]
		max_code_length = codes.map(&:length).max
		
		code = code.ljust(max_code_length)
		cur = $format_as[:at_full_length].(cur)
		tot = $format_as[:at_full_length].(tot)
		per = $format_as[:per_pad_w_space].(per)
		return "#{code} on #{cur} of #{tot} at #{per} percent"
	end,
	
	trans_state_line_full: -> (char) do
		$format_as[:at_length_w_space].(char, $format_as[:VAR][:character_soft_limit_length])
	end,
	
	trans_state_full: -> (trans_stats) do
		used = $format_as[:trans_state_line_full].(trans_stats[:used])
		left = $format_as[:trans_state_line_full].(trans_stats[:left])
		tot  = $format_as[:trans_state_line_full].(trans_stats[:tot])
		per  = $format_as[:per_pad_w_space].(trans_stats[:per])
		return "used #{used} - left #{left} - total #{tot} - at #{per}%"
	end,
	
	trans_state_line_compact: -> (char) do
		$format_as[:at_length_w_0].(char, $format_as[:VAR][:character_soft_limit_length])
	end,
	
	trans_state_compact: -> (trans_stats) do
		code = trans_stats[:code].to_s
		used = $format_as[:trans_state_line_compact].(trans_stats[:used])
		left = $format_as[:trans_state_line_compact].(trans_stats[:left])
		tot  = $format_as[:trans_state_line_compact].(trans_stats[:tot])
		per  = $format_as[:per_pad_w_0].(trans_stats[:per])
		limit_reached = trans_stats[:reached_char_soft_limit].to_s[0]
		# ct => characters translated
		return "#{code}:rcsl:#{limit_reached}&ct:#{used}+#{left}/#{tot}@#{per}%"
	end
}