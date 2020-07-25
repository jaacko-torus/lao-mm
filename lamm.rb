# Lamm - LnAMtM -  LightNovel Auto MachineTranslation Multiplex


# file manipulation
require "fileutils"

# for microsoft
require "net/http"
require "uri"
require "cgi"
require "json"
require "securerandom"

# for watson
require "json"
require "ibm_watson/authenticators"
require "ibm_watson/language_translator_v3"
include IBMWatson

# console manipulation
require "io/console"

# formating lambdas helpers
require "./utils/format_as.rb"

$translators = {
	:enabled => true,
	
	:list => {
		:microsoft => {
			:code => :m,
			:enabled => true,
			:log_file => "microsoft_log.txt",
			
			:character => {
				:hard_limit => 2_000_000,
				:soft_limit_buffer => 1000,
				:soft_limit => -> { $translators[:list][:microsoft][:character][:hard_limit] - $translators[:list][:microsoft][:character][:soft_limit_buffer] },
				:used => 0,
				:left => -> { $translators[:list][:microsoft][:character][:soft_limit].() - $translators[:list][:microsoft][:character][:used] },
				:soft_limit_reached => false
			},
			
			:subscription_key => "",
			:base_path => "https://api.cognitive.microsofttranslator.com/translate",
			:version => "?api-version=3.0",
			:lang_from => "ja",
			:lang_to => ["en"],
			:params => -> () {
				"&from=#{$translators[:list][:microsoft][:lang_from]
				}#{$translators[:list][:microsoft][:lang_to].map { |lang| "&to=#{lang}" }.join}" },
			:path => -> () {
				"#{$translators[:list][:microsoft][:base_path]
				}#{$translators[:list][:microsoft][:version]
				}#{$translators[:list][:microsoft][:params].()}" },
			:uri => -> () { URI($translators[:list][:microsoft][:path].()) },
			:translate => -> (line) do
				uri = $translators[:list][:microsoft][:uri].()
				
				request = Net::HTTP::Post.new(uri)
				request.body = %([{"Text": "#{line}"}])
				request["Content-type"] = "application/json"
				request["Content-length"] = request.body.length
				request["Ocp-Apim-Subscription-Key"] = $translators[:list][:microsoft][:subscription_key]
				request["X-ClientTraceId"] = SecureRandom.uuid
				
				response = Net::HTTP.start(
					uri.host,
					uri.port,
					:use_ssl => uri.scheme == "https"
				) do |http|
					http.request (request)
				end
				
				parsed_json = JSON.parse(response.body.force_encoding("utf-8"))
				
				File.open("#$out_dir/#{$translators[:list][:microsoft][:log_file]}", "a") { |file| file.write "#{parsed_json}\n" }
				
				return parsed_json[0]["translations"][0]["text"]
			end
		},
		:watson => {
			:code => :w,
			:enabled => false,
			:log_file => "watson_log.txt",
			
			:character => {
				:hard_limit => 1_000_000,
				:soft_limit_buffer => 500,
				:soft_limit => -> { $translators[:list][:watson][:character][:hard_limit] - $translators[:list][:watson][:character][:soft_limit_buffer] },
				:used => 0,
				:left => -> { $translators[:list][:watson][:character][:soft_limit].() - $translators[:list][:watson][:character][:used] },
				:soft_limit_reached => false
			},
			
			:lang_from => "ja",
			:lang_to => "en",
			:model_id => -> () { "#{$translators[:list][:watson][:lang_from]}-#{$translators[:list][:watson][:lang_to]}" },
			:version => "2018-05-01",
			:apikey => "",
			:service_url => "",
			:translate => -> (line) do
				authenticator = Authenticators::IamAuthenticator.new(apikey: $translators[:list][:watson][:apikey])
				
				language_translator = LanguageTranslatorV3.new(
					version: $translators[:list][:watson][:version],
					authenticator: authenticator
				)
				
				language_translator.service_url = $translators[:list][:watson][:service_url]
				
				translation = language_translator.translate(
					text: line,
					model_id: $translators[:list][:watson][:model_id].()
				)
				
				# just in case I'll add everything to a txt file that I can analyse later
				File.open("#$out_dir/#{$translators[:list][:watson][:log_file]}", "a") { |file| file.write "#{translation.result}\n" }
				
				# this will return only one translation
				# I have not yet encountered a situation where I get more than one translation
				return translation.result["translations"][0]["translation"]
			end
		}
	},
	
	:translate => -> (line) do
		escaped_line = line.gsub(/["\\\/]/) { |match| "\\#{match}" }
		
		return $translators[:get].(:usable).map do |translator_name, translator|
			if $translators[:enabled]
				translator[:translate].(escaped_line)
			else
				escaped_line
			end
		end
	end,
	
	:get => -> (mode = :all) do
		case mode
		when :all
			return $translators[:list]
		when :enabled
			return $translators[:get].(:all).select do |translator_name, translator|
				translator[:enabled]
			end
		when :usable
			return $translators[:get].(:enabled).reject do |translator_name, translator|
				translator[:character][:soft_limit_reached]
			end
		else
			return nil
		end
	end,
	
	:update => -> (line, what) {
		case what
		when :soft_limit_reached
			$translators[:get].(:usable).map do |translator_name, translator|
				translator[:character][:soft_limit_reached] =
				translator[:character][:used] + line.strip.length >= translator[:character][:soft_limit].()
			end
		end
	},
	
	:check => -> (what) {
		case what
		when :soft_limit_reached
			$translators[:get].(:usable)\
				.map { |translator_name, translator| translator[:character][:soft_limit_reached] }\
				.all?(true)
		end
	}
}

$line_numbers = true

$ocr_dir = "#{__dir__}/ocr"
$out_dir = "#{__dir__}/out"

$status_file_txt = "status.txt"
$status_file_md  = "status.md"
$status = { :volume => 0, :page => 0, :line => 0 }

$regex_tag = /<.*>/
$regex_pagemarker = /\[==\| Page \d+ \|==\]/
$regex_pagemarker_number = /(?<=^\[==\| Page )\d+(?= \|==\]$)/
$regex_not_empty_tag_pagemarker = /^(?!$|#$regex_tag$|#$regex_pagemarker$).*$/

def main
	organize_file_structure()
	traverse()
end

def organize_file_structure
	FileUtils.mkdir("out") unless Dir.exist?("out")
end

def traverse
	# pre-save ocr/raw globs cuz they're probably pretty intensive
	ocr_dir_glob = Dir.glob("#$ocr_dir/*")
	out_dir_glob = Dir.glob("#$out_dir/*")
	
	# volumes that are completed according to $out_dir_glob
	completed_volumes_acc_to_out = (
		# AND the 2 globs to know whose volumes have already been processed
		# not all files in ocr are necesarily part of the proj
		ocr_dir_glob.map { |volume| File.basename(volume, File.extname(volume)) } &
		out_dir_glob.map { |volume| File.basename(volume, File.extname(volume)) }
	)
	
	# if the file is there and is not last, it must be completed.
	*completed_volumes, volume_inprogress = completed_volumes_acc_to_out
	
	# vars
	all_stats = all_stats_for_all_volumes(ocr_dir_glob)
	max_stats = max_stats_for_all_volumes(all_stats)
	volume_tot = all_stats.length
	
	# format vars
	$format_as[:VAR][:character_soft_limit_length] = $character_soft_limit.to_s.length
	$format_as[:VAR][:max_tot__length] = max_stats.map { |k, v| v.to_s.length }.max
	
	$format_as[:VAR][:max_volume__length] = max_stats[:volume].to_s.length
	$format_as[:VAR][:max_page__length]   = max_stats[:page].to_s.length
	$format_as[:VAR][:max_line__length]   = max_stats[:line].to_s.length
	$format_as[:VAR][:max_char__length]   = max_stats[:char].to_s.length
	
	# first time modify status
	status_check(completed_volumes, volume_inprogress)
	
	ocr_dir_glob.each.with_index do |volume, volume_idx|
		# only do first volume for now
		next unless volume_idx == 0
		
		# make sure to never translate more than you should
		break if $character_soft_limit_reached
		
		# vars
		title = File.basename(volume, File.extname(volume))
		
		volume_cur = volume_idx + 1
		volume_per = "%6.2f" % (volume_cur.to_f / volume_tot.to_f * 100.00).round(2)
		
		# skip if before this volume, make sure that all the volume is translated before moving on
		next if volume_cur < $status[:volume]
		
		case all_stats[volume_idx] # pattern matching to set page_tot, line_tot, and char_tot
		in { page: page_tot, line: line_tot, char: char_tot }
		end
		
		# start at -1 since this is an index, 0 (the first index) will only come after I'm using it, so inside of the loop
		# I'm defining some variable all in the same place, which use idx, so I'm doing this to make sure the first increment has it becoming 0
		page_idx, line_idx, char_idx = [-1] * 3
		
		File.open(volume, "r").each do |line|
			raw_line = line.strip
			
			# next if all soft limits are reached
			$translators[:update].(line, :soft_limit_reached) if raw_line =~ $regex_not_empty_tag_pagemarker
			
			break if $translators[:check].(:soft_limit_reached)
			
			to_cur = -> (idx) { idx + 1 }
			to_per = -> (cur, tot) { (cur.to_f / tot.to_f * 100.00).round(2) }
			
			page_idx += 1 if raw_line =~ /^#$regex_pagemarker$/
			line_idx += 1 if raw_line =~ $regex_not_empty_tag_pagemarker
			char_idx += raw_line.chars.length if raw_line =~ $regex_not_empty_tag_pagemarker
			
			page_cur, line_cur, char_cur = [page_idx, line_idx, char_idx].map { |idx| to_cur.(idx) }
			page_per, line_per, char_per = [
				[page_cur, page_tot],
				[line_cur, line_tot],
				[char_cur, char_tot]
			# I wish the was one of those to_proc this for user defined lambdas
			].map { |per| to_per.(*per) }
			
			# skip if same line, assuming IBM will always translate correctly
			next if line_cur <= $status[:line]
			
			# add the number of characters translated and translate only if line is not metadata or formatting
			if raw_line =~ $regex_not_empty_tag_pagemarker
				$translators[:get].(:usable).each { |translator_name, translator| translator[:character][:used] += raw_line.length }
				
				translated_line = $translators[:translate].(raw_line)
			end
			
			File.open("#$out_dir/#{title}.md", "a") do |file|
				# if empty, copy it to file
				if raw_line.empty?
					file.write("\n")
				# if page title transform to "## - Page n -" where n is a number
				elsif raw_line =~ /^#$regex_pagemarker$/
					file.write("## \- Page #{raw_line.scan($regex_pagemarker_number).join} \-\n")
				# if line starts with "<" and ends with ">" with anything in between, the surround with backquotes
				elsif raw_line =~ /^#$regex_tag$/
					file.write("`#{raw_line}`\n")
				# assume that it's text to translate otherwise
				else
					markdown_escaped_regex = /[.(){}`_#!]|[\+\*\|\[\]\-]/
					file.write(translated_line\
						.map { |line| line.gsub(markdown_escaped_regex) { |match| "\\#{match}" } }\
						.map { |line| "#{$line_numbers ? "**\(#{line_cur}.\)** " : ""}#{line} <br>\n" }\
						.join)
					file.write("> #{raw_line.gsub(markdown_escaped_regex) { |match| "\\#{match}" }}\n")
				end
			end
			
			# report only after making sure that it has been translated
			# if this function fails then the status reader will get slighly behind stats
			# it's better to have a line repeated than not having it at all
			
			if line =~ $regex_not_empty_tag_pagemarker
				# this is slightly cleaner for understanding that just a bunch of variables
				report($translators[:get].()\
					.map { |translator_name, translator| {
						:code => translator[:code],
						:used => translator[:character][:used],
						:left => translator[:character][:left].(),
						:tot  => translator[:character][:soft_limit].(),
						:per  => to_per.(
							translator[:character][:used],
							translator[:character][:soft_limit].()),
						:reached_char_soft_limit => translator[:character][:soft_limit_reached]
					} }, {
						:v => {cur: volume_cur, tot: volume_tot, per: volume_per},
						:p => {cur:   page_cur, tot:   page_tot, per:   page_per},
						:l => {cur:   line_cur, tot:   line_tot, per:   line_per},
						:c => {cur:   char_cur, tot:   char_tot, per:   char_per}
					}, title, line, translated_line)
			end
		end
		
		# reset page, line status, and add one to the volume count since we are done with this volume
		# I'm not doing this at the begining since there is a check up there to make sure that we are in the right line the first time, and reseting these values would essentially reset the values which are being calculated
		$status[:volume] += 1
		$status[:line] = 1
	end
end

def status_check(completed_volumes, volume_inprogress)
	# if I can read from file, do that
	if File.exist?("#$out_dir/#$status_file_txt")
		# if file exists simply copy from file
		# trans-state:ccc+rrr/ttt@ppp.pp%
		# state:v:ccc/ttt@ppp.pp%p:ccc/ttt@ppp.pp%l:ccc/ttt@ppp.pp%c:ccc/ttt@ppp.pp%
		# where c = current, r = remaining, t = total, and p = percentage
		File.open("#$out_dir/#$status_file_txt", "r") { |file|
			file_read = file.read
			
			# Translation State
			$translators[:get].(:enabled).each { |translator_name, translator|
				trans_state = file_read.scan(/(?<=^trans-state:).+$/)[0]
				
				code = translator[:code].to_s
				trans_state_section = trans_state.scan(/(?<=#{code}:)rcsl:[tf]&ct:\d+\+\d+\/\d+@\d{3}\.\d{2}%(?=$|[a-z]:)/)[0]
				
				trans_state_section_rcsl = case trans_state_section.scan(/(?<=^rcsl:).(?=&)/)[0]
				when "t" then true
				when "f" then false
				else nil
				end
				trans_state_section_ct = trans_state_section.scan(/(?<=&ct:).+(?=$)/)[0]
				
				trans_state_section_ct_cur = trans_state_section_ct.scan(/(?<=^)\d+(?=\+)/)[0].to_i
				trans_state_section_ct_tot = trans_state_section_ct.scan(/(?<=\/)\d+(?=@)/)[0].to_i
				
				translator[:character][:used] = trans_state_section_ct_cur
				translator[:character][:soft_limit_reached] = trans_state_section_rcsl
				
				translator[:character][:soft_limit_buffer] =
					translator[:character][:hard_limit] - trans_state_section_ct_tot
			}
			
			# Reading State
			state = file_read.scan(/(?<=^state:).+(?=$)/)[0]
			
			state_volume = state.scan(/(?<=^v:)\d+\/\d+@\d{3}\.\d{2}%(?=p:)/)[0]
			state_page   = state.scan(/(?<=p:)\d+\/\d+@\d{3}\.\d{2}%(?=l:)/)[0]
			state_line   = state.scan(/(?<=l:)\d+\/\d+@\d{3}\.\d{2}%(?=c:)/)[0]
			state_char   = state.scan(/(?<=c:)\d+\/\d+@\d{3}\.\d{2}%(?=$)/)[0]
			
			$status[:volume] = state_volume.scan(/(?<=^)\d+(?=\/)/)[0].to_i
			$status[:page]   =   state_page.scan(/(?<=^)\d+(?=\/)/)[0].to_i
			$status[:line]   =   state_line.scan(/(?<=^)\d+(?=\/)/)[0].to_i
			$status[:char]   =   state_char.scan(/(?<=^)\d+(?=\/)/)[0].to_i
		}
	
	# if folder is empty (folder should exist by now)
	elsif Dir.empty?($out_dir)
		$status[:volume] = 1
	
	# if file is not found, analyse latest volume
	else
		$status[:volume] = completed_volumes.length + 1
		$status[:page], $status[:line] = count_stats_for_volume("#$out_dir/#{volume_inprogress}.md")
	end
end

# TODO: this should be "all stats for all volumes" and then have whatever var calls this find the max
def all_stats_for_all_volumes(volumes)
	return volumes.map do |volume|
		page_tot, line_tot, char_tot = count_stats_for_volume(volume)
		{ page: page_tot, line: line_tot, char: char_tot }
	end
end

def max_stats_for_all_volumes(volumes)
	volumes.reduce({page: 0, line: 0, char: 0}) { |max, cur|
		max.zip(cur).map { |volume|
			# TODO: do this in a smarter way please
			code, *code_value = volume.flatten.uniq
			[code, code_value.max]
		}.to_h
	}
end

def count_stats_for_volume(volume)
	# assume they are all 0 at the begginig
	page_tot, line_tot, char_tot = [0] * 3
	
	File.open(volume, "r").each do |line|
		# if is page marker
		page_tot += 1 if line =~ $regex_pagemarker
		
		# not empty, title marker, or tag
		if line =~ $regex_not_empty_tag_pagemarker
			# simply count
			line_tot += 1
			# count number of characters per line
			char_tot += line.strip.chars.length
		end
	end
	# could return them as a hash?
	return page_tot, line_tot, char_tot
end

def report(trans_stats, stats, title, line, translated_line)
	# first report to file since that one is permanent, if the console quits unexpectedly there are more chances of it having the right information
	report_to_file(trans_stats, stats, title, line, translated_line)
	report_to_console(trans_stats, stats, title, line, translated_line)
end

def report_to_file(trans_stats, stats, title, line, translated_line)
	# for the computer
	
	status_file_txt_content = <<~HereDoc
		#{title}
		trans-state:#{trans_stats.map { |trans_stats_set| $format_as[:trans_state_compact].(trans_stats_set) }.join}
		state:#{$format_as[:stat_compact].(stats)}
		from:"#$ocr_dir/#{title}.txt"
		#{line.strip}
		to:"#$out_dir/#{title}.md"
		#{translated_line.join("\n")}
	HereDoc
	
	# for me
	status_file_md_content = <<~HereDoc
		Title: _"#{title}"_
		
		Translator State: `#{trans_stats.map { |trans_stats_set| $format_as[:trans_state_compact].(trans_stats_set) }.join}` <br>
		State: `#{$format_as[:stat_compact].(stats)}`
		
		#{trans_stats.map { |translator|
			if_can_continue = "can" + (translator[:reached_char_soft_limit] ? "not" : " still") + " continue"
			[
				"#{translator[:code]} #{if_can_continue} translating <br>",
				"With **#{
					translator[:used]
				} characters read** there are still **#{
					translator[:left]
				} characters left** for a total of #{
					translator[:tot]
				} characters at #{
					translator[:per]
				} percent"
			].join("\n")
		}.join("\n\n") }
		
		Currently on: <br>
			Volume **n°#{stats[:v][:cur]}**/#{stats[:v][:tot]} (#{stats[:v][:per]}%) <br>
			Page   **n°#{stats[:p][:cur]}**/#{stats[:p][:tot]} (#{stats[:p][:per]}%) <br>
			Line   **n°#{stats[:l][:cur]}**/#{stats[:l][:tot]} (#{stats[:l][:per]}%) <br>
			Char   **n°#{stats[:c][:cur]}**/#{stats[:c][:tot]} (#{stats[:c][:per]}%)
		
		Translated from: _["#$ocr_dir/#{title}.txt"](#{"#$ocr_dir/#{title}.txt".gsub(" ", "%20")})_ <br>
		> #{line.strip}
		
		To: _["#$out_dir/#{title}.md"](#{"#$out_dir/#{title}.md".gsub(" ", "%20")})_ <br>
		> #{translated_line.join("\n")}
	HereDoc
	
	File.open("#$out_dir/#$status_file_txt", "w") { |file| file.write status_file_txt_content }
	File.open("#$out_dir/#$status_file_md",  "w") { |file| file.write status_file_md_content }
end

def report_to_console(trans_stats, stats, title, line, translated_line)
	system("cls") || system("clear")
	puts title
	
	puts $format_as[:stat_full].("volume", stats[:v][:cur], stats[:v][:tot], stats[:v][:per])
	puts $format_as[:stat_full].(  "page", stats[:p][:cur], stats[:p][:tot], stats[:p][:per])
	puts $format_as[:stat_full].(  "line", stats[:l][:cur], stats[:l][:tot], stats[:l][:per])
	puts $format_as[:stat_full].(  "char", stats[:c][:cur], stats[:c][:tot], stats[:c][:per])
	
	translated_line.each { |translation| puts translation }
	puts "\t" + line.strip
end

main()