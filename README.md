# lao&mm
v1.0.0

lao - LnAutoOcr - LightNovel Auto OCR(Optical Character Recognition)
lamm - LnAMtM -  LightNovel Auto MachineTranslation Multiplex

**notice**: this was made for self use, it is highly spaghetti-like, and might absolutely melt and explode your computer. Read before running, you've been warned.

The goal behind Lao&mm was to translate light novels from japanese to english, including those for which there were only scans. First use OCR and then translate.

However it should be flexible enough to translate from any language which [Capture2Text](http://capture2text.sourceforge.net/) can recognize and Watson Translate and Microsoft Translate can translate. [Capture2Text](http://capture2text.sourceforge.net/) is free and opensource. The two translators are free up until a certain amount of characters. I did not include Google translate cuz I'm not paying and I get too few characters

As of the last time I checked (check commit tree if you're interested when that was) the rates were as follows:
- Google    allows up to   500_000 characters           for free then 20USB per million
- Watson    allows up to 1_000_000 characters per month for free then 20USD per million
- Microsoft allows up to 2_000_000 characters per month for free then 10USD per million

All of them are good :)

Requires
- Ruby 2.7
- [Capture2Text](http://capture2text.sourceforge.net/)

If you are planning to actually use this, please do read below. I don't trust my software too much myself, so make copies before proceeding to the next step.

folder structure:
```
<folder name>
	lao.rb
	lamm.rb
	utils
		format_as.rb
	raw
		<your raw images to ocr here>
	ocr
		<your txt file to translate|the resulting ocr'ed files here>
	out
		<translated markdown documents>
```

## Lao
Lao - LnAutoOcr - LightNovel Auto OCR(Optical Character Recognition)

`ruby lao.rb` to run

Lao is in charge of recognizing characters and putting them under `ocr/<name of book>`

To start find an empty folder and create a `raw` folder.

The expected format of the raw files is
```
	raw
		<Volume 1>
			<img 1>
			<img 2>
			...
		<Volume 2>
		...
```
Where the only important thing is that their name are in ascending order. For example `<img2>` could be called "rockefeller 2020", all that matters is that the images are in the right ascending order.

- `$Capture2Text_CLI` defines the location of `Capture2Text_CLI.exe`, by default it's _"[C:/Users/julia/Downloads/Capture2Text_v4.6.2_64bit/Capture2Text/Capture2Text_CLI.exe](C:/Users/julia/Downloads/Capture2Text_v4.6.2_64bit/Capture2Text/Capture2Text_CLI.exe)"_, I'm not sure what would happen if it's not there, just change either the variable of the file location. You should probably try to use the same _"Capture2Text"_ version as well just in case.

**also** by default the command to ocr characters is in vertical mode and japanese language. Take a look at first line under `ocr()`. Use the Capture2Text documentation towards the bottom if you wanna personalize all of that for russian novels or somethin.

Any pages where no text is recognized at all will simply write `<IMAGE>`

Pages are separated with `[==| Page <n> |==]` where `n` is the page number.

The results will be put into _"./ocr"_ as individual `.txt` files

## Lamm
lamm - LnAMtM -  LightNovel Auto MachineTranslation Multiplex

`ruby lamm.rb` to run

Assuming that you just finished OCRing all of your books, now you just run the command and the new resulting and translated files will be put under _"./out"_.

In order for watson to do it's thing you should first `gem install ibm_watson`. Otherwise I'm not sure what's gonna happen, but I bet it's not pretty. Or you could disable `:watson` more on that in a sec.

First, the resulting translated documents are in markdown. They are separated in pages and have first the translated versions and then (quoted) the original text.

If you are starting here, you need a folder called `ocr` with `.txt` documents only.

If you are changing the source and want to test for errors **before** actually translating change `$translators[:enabled] => false`

Now, for credentials, goto
	- `$translators[:list][:microsoft][:subscription_key]`
	- `$translators[:list][:watson][:apikey]`
	- `$translators[:list][:watson][:service_url]`

for those. In `$translators[:list]` you'll find other useful stuff :D.

## Other important stuffs

**translating/ocr progress**: lao&mm keeps a `status.txt` & `.md` (for humans) to not only tell you how far you are, but also to make sure that if there's an unexpected exit, you'll be able to continue where you left off. Gotta make sure you don't use up more characters than you should :D

**character escaping**: lamm makes sure to escape all characters before sending them to the server, don't worry about those. There's no way to disallow the feature tho :P

**other languages**: as said in the intro if Capture2Text and IBM/Microsoft can handle those languages, so can this guy. to change language to and from goto `$translators[:list][<translator>][:lang_from]` and `[:lang_to]`.

**why did you upload this? it's shit!** yeah I know... it's mostly for me, anyone can come up with this much. But for all of you teenager kids out there I hope this is useful to read that last Light Novel of _"Ascendence of a Bookworm"_ cuz you know there are 20 volumes out there and not enough of them have been translated so you've succumbed into the abyss that is machine translated literature.

If you have questions feel free to talk to me at jaacko.torus@gmail.com or jaackotorus#8796 in discord. If you want to help me make a real utility from this I would be super happy also.