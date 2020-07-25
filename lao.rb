# Lao - LnAutoOcr - LightNovel Auto OCR(Optical Character Recognition)

require "fileutils"

# LAO lang C2T raw ocr
# lao -l "Japanese" -cl "C:/Users/julia/Downloads/Capture2Text_v4.6.2_64bit/Capture2Text/Capture2Text_CLI.exe" -r "./raw" -o "./ocr"
# -l -lang --language : language to recognize
# -cl -c2t-location --capture2text-location : where Capture2Text
# -r --raw : location of raw images
# -o --ocr : location of ocr output

$Capture2Text_CLI = "C:/Users/julia/Downloads/Capture2Text_v4.6.2_64bit/Capture2Text/Capture2Text_CLI.exe"

$lang = "Japanese"

$weird_top_char = true

$raw_dir = "#{__dir__}/raw"
$ocr_dir = "#{__dir__}/ocr"

$tmp_file = "tmp"
$state_file = "status"
$state_file_md = "status.md"

$status = { :volume => 0, :page => 0 }

def main
	organize_file_structure()
	traverse_ocr()
	cleanup()
end

def organize_file_structure
	FileUtils.mkdir("ocr") unless Dir.exist?("ocr")
end

def traverse_ocr
	# pre-save ocr/raw globs cuz they're probably pretty intensive
	raw_dir_glob = Dir.glob("#$raw_dir/*")
	ocr_dir_glob = Dir.glob("#$ocr_dir/*")
	
	# volumes that are completed according to $ocr_dir_glob
	completed_volumes_acc_to_ocr = (
		# AND the 2 globs to know whose volumes have already been processed
		# not all files in ocr are necesarily part of the proj
		raw_dir_glob.map { |volume_dir| File.basename(volume_dir) } &
		ocr_dir_glob.map { |volume_file| File.basename(volume_file, File.extname(volume_file)) }
	)
	
	# if the file is there and is not last, it must be completed.
	# NOTE: could use splat here, putting it in separate lines for readability
	completed_volumes = completed_volumes_acc_to_ocr[0...-1]
	volume_inprogress = completed_volumes_acc_to_ocr[-1]
	
	#vars
	volume_tot = raw_dir_glob.length
	
	# one time modify status
	status_check(completed_volumes, volume_inprogress)
	
	raw_dir_glob.each.with_index do |volume_dir, volume_dir_idx|
		# pre-save globs
		volume_dir_glob = Dir.glob("#{volume_dir}/*")
		
		# vars
		page_tot = volume_dir_glob.length
		volume_name = File.basename(volume_dir)
		volume_cur = volume_dir_idx + 1
		volume_per = "%.2f" % (volume_cur.to_f / volume_tot.to_f * 100.00).round(2)
		
		# skip if has not reached volume
		next if volume_dir_idx < $status[:volume] - 1
		
		# glob volume_dir to get all images
		volume_dir_glob.each_with_index do |page_img, page_img_idx|
			page_name = File.basename(page_img)
			page_cur = page_img_idx + 1
			page_per = "%.2f" % (page_cur.to_f / page_tot.to_f * 100.00).round(2)
			
			# skip if has not reached page + page
			next if page_img_idx <= $status[:page] - 1
			
			# optical char recognition
			tmp_content = ocr(volume_name, page_cur, page_img, page_img_idx)
			
			# let the user know what's going on
			report(
				page_img,
				volume_name, volume_cur, volume_tot, volume_per,
				page_name, page_cur, page_tot, page_per,
				tmp_content
			)
		end
		
		$status[:page] = 0
	end
end

def status_check(completed_volumes, volume_inprogress)
	# by default values are 0
	if File.exist?("#$ocr_dir/#$state_file")
		# if file exists simply copy from file
		# Vnnn/ttt@ppp.pp%Pnnn/ttt@ppp.pp%
		# where n = number, t = total, and p = percentage
		$status[:volume] = File.open("#$ocr_dir/#$state_file", "r") { |file| file.read.scan(/(?<=v)\d+(?=\/\d+@\d+\.\d+%)/)[0].to_i }
		$status[:page] = File.open("#$ocr_dir/#$state_file", "r") { |file| file.read.scan(/(?<=p)\d+(?=\/\d+@\d+\.\d+%)/)[0].to_i }
	
	elsif Dir.empty?($ocr_dir)
		$status[:volume] = 1
	
	else
		# otherwise use $ocr_dir_glob to check what's the last volume available
		$status[:volume] = completed_volumes.length + 1
		# then find last modified volume and search for last page
		$status[:page] = File.open("#$ocr_dir/#{volume_inprogress}.txt", "r") do |file|
			file.read.scan(/(?<=\[==| Page )\d+(?= |==\])/)[-1].to_i
		end
	end
end

def ocr(volume_name, page_cur, page_img, page_img_idx)
	# write to tmp file
	system %("#$Capture2Text_CLI" --line-breaks --vertical --language "#$lang" --image "#{page_img}" --output-file "#$ocr_dir/#$tmp_file")
	
	# read tmp and save in memory
	tmp_content = File.open("#$ocr_dir/#$tmp_file", "r") { |file| file.read.strip }
	# format so that it's easier to machine translate
	tmp_content = tmp_content.
		split("\n\n").
		map { |paragraph| paragraph.split("\n") }.
		map { |sentence| sentence.join(" ") }.
		join("\n\n")
	# if the weird character on front keeps appearing, just remove first character
	tmp_content = tmp_content[1..-1] if $weird_top_char
	# "<Error>" means there's an image most of the time.
	# If it doesn't make any sense due to context I can go to the image in question
	tmp_content = "<IMAGE>" if tmp_content.include? "<Error>"
	
	# append to file
	page_pad = "\n" * 3
	top_pad = page_img_idx != 0 ? page_pad : ""
	page_marker = "[==| Page #{page_cur} |==]"
	bottom_pad = page_pad
	separator = "#{top_pad}#{page_marker}#{bottom_pad}"
	
	File.open("#$ocr_dir/#{volume_name}.txt", "a") { |file| file.write("#{separator}#{tmp_content.
		split("\n\n").
		map { |paragraph| paragraph.split("\n") }.
		map { |sentence| sentence.join(" ") }.
		join("\n\n")
	}") }
	
	return tmp_content
end

def report(
	page_img,
	volume_name, volume_cur, volume_tot, volume_per,
	page_name, page_cur, page_tot, page_per,
	tmp_content
)
	# print to console
	console_report(volume_name, page_cur, page_tot, page_per)
	
	# and make a permanent copy
	report_status(
		page_img,
		volume_name, volume_cur, volume_tot, volume_per,
		page_name, page_cur, page_tot, page_per,
		tmp_content
	)
end

def console_report(volume_name, page_cur, page_tot, page_per)
	system "cls"
	puts volume_name
	puts "Currently on page #{page_cur} of #{page_tot} at #{page_per}%"
end

def report_status(
	page_img,
	volume_name, volume_cur, volume_tot, volume_per,
	page_name, page_cur, page_tot, page_per,
	tmp_content
)
	status_txt_content = <<~HereDoc
		state v#{
			"%03i" % volume_cur }/#{ "%03i" % volume_tot }@#{ "%06.2f" % volume_per
		}%p#{
			"%03i" % page_cur }/#{ "%03i" % page_tot }@#{ "%06.2f" % page_per }%
		scanned "#{page_img}"
		content:
			#{tmp_content.gsub("\n", "\n\t").strip}
	HereDoc
	
	status_md_content = <<~HereDoc
		State: **`Vol#{volume_cur}Pg#{page_cur}`** <br>
		Finished scanning: _`"#{page_img}"`_
		
		Volume **`n°#{volume_cur}/#{volume_tot}`** (`#{volume_per}%`): _`"#{volume_name}.txt"`_ <br>
		Page **`n°#{page_cur}/#{page_tot}`** (`#{page_per}`%): _`"#{page_name}"`_
		
		Content:
		#{tmp_content.split("\n").map { |line| line.prepend "> " }.join("\n").strip }
	HereDoc
	File.open("#$ocr_dir/#$state_file", "w") { |file| file.write(status_txt_content) }
	File.open("#$ocr_dir/#$state_file_md", "w") { |file| file.write(status_md_content) }
end

def cleanup
	File.delete("#$ocr_dir/#$tmp_file") if
		File.exist?("#$ocr_dir/#$tmp_file")
	
	File.delete("#$ocr_dir/#$state_file") if
		File.exist?("#$ocr_dir/#$state_file")
	
	File.delete("#$ocr_dir/#$state_file_md") if
		File.exist?("#$ocr_dir/#$state_file_md")
	
	system "cls"
	puts %(Finished OCR on every folder inside of "#$raw_dir" and outputed the result in their corresponding txt file inside of "#$ocr_dir":)
	puts Dir.glob("#$raw_dir/*").map { |dir| %(\t"#{File.basename(dir)}") }
end

main()