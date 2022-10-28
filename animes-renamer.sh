#!/bin/bash

SCRIPT_FOLDER=$(dirname $(readlink -f $0))
source $SCRIPT_FOLDER/config.conf
LOG=$LOG_FOLDER/animes/$(date +%Y.%m.%d).log
MATCH_LOG=$LOG_FOLDER/animes/missing-ID-link.log
ADDED_LOG=$LOG_FOLDER/animes/added.log
DELETED_LOG=$LOG_FOLDER/animes/deleted.log

# function
function get-mal-id () {
jq ".[] | select( .tvdb_id == ${tvdb_id} )" -r $SCRIPT_FOLDER/tmp/pmm_anime_ids.json | jq .mal_id | sort -n | head -1
}
function get-mal-infos () {
if [ ! -f $SCRIPT_FOLDER/data/animes/$mal_id.json ] 										#check if exist
then
	sleep 0.5
	curl "https://api.jikan.moe/v4/anime/$mal_id" > $SCRIPT_FOLDER/data/animes/$mal_id.json 
	sleep 1.5
fi
}
function get-mal-title () {
jq .data.title -r $SCRIPT_FOLDER/data/animes/$mal_id.json
}
function get-mal-rating () {
jq .data.score -r $SCRIPT_FOLDER/data/animes/$mal_id.json
}
function get-mal-poster () {
if [ ! -f $SCRIPT_FOLDER/posters/$mal_id.jpg ]										#check if exist
then
sleep 0.5
	mal_poster_url=$(jq .data.images.jpg.large_image_url -r $SCRIPT_FOLDER/data/animes/$mal_id.json)
	curl "$mal_poster_url" > $SCRIPT_FOLDER/posters/$mal_id.jpg
sleep 1.5
fi
}
function get-mal-tags () {
(jq '.data.genres  | .[] | .name' -r $SCRIPT_FOLDER/data/animes/$mal_id.json && jq '.data.themes  | .[] | .name' -r $SCRIPT_FOLDER/data/animes/$mal_id.json  && jq '.data.demographics  | .[] | .name' -r $SCRIPT_FOLDER/data/animes/$mal_id.json) | awk '{print $0}' | paste -s -d, -
}
function get-tvdb-id () {
jq ".[] | select( .mal_id == ${mal_id} )" -r $SCRIPT_FOLDER/tmp/pmm_anime_ids.json | jq '.tvdb_id' | sort -n | head -1
}
function get-mal-studios() {
jq '.data.studios[0] | [.name]| @tsv' -r $SCRIPT_FOLDER/data/animes/$mal_id.json | sed "s/Brain's Base/Brains Base/"
}

# download pmm animes mapping and check if files and folder exist
if [ ! -f $animes_titles ]											#check if metadata files exist and echo first line
then
        echo "metadata:" > $animes_titles
else
	rm $animes_titles
	echo "metadata:" > $animes_titles
fi
if [ ! -d $SCRIPT_FOLDER/data ]											#check if exist and create folder for json data
then
        mkdir $SCRIPT_FOLDER/data
fi
if [ ! -d $SCRIPT_FOLDER/data/animes ]	
then
	mkdir $SCRIPT_FOLDER/data/animes
else
	find $SCRIPT_FOLDER/data/animes/* -mmin +720 -exec rm {} \;						#delete json data if older than 1 days
fi
if [ ! -d $SCRIPT_FOLDER/posters ]										#check if exist and create folder for posters
then
        mkdir $SCRIPT_FOLDER/posters
else
	find $SCRIPT_FOLDER/posters/* -mtime +30 -exec rm {} \;							#delete posters if older than 30 days
fi
if [ ! -d $SCRIPT_FOLDER/ID ]											#check if exist and create folder and file for ID
then
	mkdir $SCRIPT_FOLDER/ID
	touch $SCRIPT_FOLDER/ID/animes.tsv
elif [ ! -f $SCRIPT_FOLDER/ID/animes.tsv ]
then
	touch $SCRIPT_FOLDER/ID/animes.tsv
else 
	rm $SCRIPT_FOLDER/ID/animes.tsv
	touch $SCRIPT_FOLDER/ID/animes.tsv
fi
if [ ! -d $SCRIPT_FOLDER/tmp ]											#check if exist and create temp folder cleaned at the start of every run
then
        mkdir $SCRIPT_FOLDER/tmp
else
	rm $SCRIPT_FOLDER/tmp/*
fi
if [ ! -d $LOG_FOLDER ]
then
	mkdir $LOG_FOLDER
fi
if [ ! -d $LOG_FOLDER/animes ]
then
	mkdir $LOG_FOLDER/animes
fi

# Download anime mapping json data
curl "https://raw.githubusercontent.com/meisnate12/Plex-Meta-Manager-Anime-IDs/master/pmm_anime_ids.json" > $SCRIPT_FOLDER/tmp/pmm_anime_ids.json		#download local copy of ID mapping

# Dummy run of PMM and move meta.log for creating tvdb_id and title_plex
rm $PMM_FOLDER/config/temp-animes.cache
$PMM_FOLDER/pmm-venv/bin/python3 $PMM_FOLDER/plex_meta_manager.py -r --config $PMM_FOLDER/config/temp-animes.yml
mv $PMM_FOLDER/config/logs/meta.log $SCRIPT_FOLDER/tmp

# create clean list-animes.tsv (tvdb_id	title_plex) from meta.log
line_start=$(grep -n "Mapping Animes Library" $SCRIPT_FOLDER/tmp/meta.log | cut -d : -f 1)
line_end=$(grep -n -m1 "Animes Library Operations" $SCRIPT_FOLDER/tmp/meta.log | cut -d : -f 1)
head -n $line_end $SCRIPT_FOLDER/tmp/meta.log | tail -n $(( $line_end - $line_start - 1 )) | head -n -5 > $SCRIPT_FOLDER/tmp/cleanlog-animes.txt
awk -F"|" '{ OFS = "\t" } ; { gsub(/ /,"",$5) } ; { print substr($5,8),substr($7,2,length($7)-2) }' $SCRIPT_FOLDER/tmp/cleanlog-animes.txt > $SCRIPT_FOLDER/tmp/list-animes.tsv

# create ID/animes.tsv from the clean list ( tvdb_id	mal_id	title_mal	title_plex )
while IFS=$'\t' read -r tvdb_id mal_id title_mal								# First add the override animes to the ID file
do
	if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/ID/animes.tsv | grep -w  $tvdb_id
	then
		line=$(grep -w -n $tvdb_id $SCRIPT_FOLDER/tmp/list-animes.tsv | cut -d : -f 1)
		title_plex=$(sed -n "${line}p" $SCRIPT_FOLDER/tmp/list-animes.tsv | awk -F"\t" '{print $2}')
		printf "$tvdb_id\t$mal_id\t$title_mal\t$title_plex\n" >> $SCRIPT_FOLDER/ID/animes.tsv
		echo "$(date +%Y.%m.%d" - "%H:%M:%S) - override found for : $title_mal / $title_plex" >> $LOG
	fi
done < $SCRIPT_FOLDER/override-ID-animes.tsv
while IFS=$'\t' read -r tvdb_id title_plex									# then get the other ID from the ID mapping and download json data
do
	if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/ID/animes.tsv | grep -w  $tvdb_id
	then
		mal_id=$(get-mal-id)
		if [[ "$mal_title" == 'null' ]] || [[ "$mal_id" == 'null' ]] || [[ "${#mal_id}" == '0' ]]	# Ignore anime with no tvdb to mal id conversion show in the error log you need to add them by hand in override
		then
			echo "$(date +%Y.%m.%d" - "%H:%M:%S) - invalid MAL ID for : tvdb : $tvdb_id / $title_plex" >> $MATCH_LOG
			continue
		fi
		get-mal-infos
		title_mal=$(get-mal-title)
		printf "$tvdb_id\t$mal_id\t$title_mal\t$title_plex\n" >> $SCRIPT_FOLDER/ID/animes.tsv
		echo "$(date +%Y.%m.%d" - "%H:%M:%S) - $title_mal / $title_plex added to ID/animes.tsv" >> $LOG
	fi
done < $SCRIPT_FOLDER/tmp/list-animes.tsv

#Create an ongoing list at $SCRIPT_FOLDER/data/animes/ongoing.csv
if [ ! -f $SCRIPT_FOLDER/data/animes/ongoing.tsv ]              #check if already exist data folder is stored for 2 days
then
        ongoingpage=1
        while [ $ongoingpage -lt 10 ];                  #get the airing list from jikan API max 9 pages (225 animes)
        do
                curl "https://api.jikan.moe/v4/anime?status=airing&page=$ongoingpage&order_by=member&order=desc&genres_exclude=12&min_score=4" > $SCRIPT_FOLDER/tmp/ongoing-tmp.json
                sleep 2
                jq ".data[].mal_id" -r $SCRIPT_FOLDER/tmp/ongoing-tmp.json >> $SCRIPT_FOLDER/tmp/ongoing.tsv            # store the mal ID of the ongoing show
                if grep "\"has_next_page\":false," $SCRIPT_FOLDER/tmp/ongoing-tmp.json                  #stop if page is empty
                then
                        break
                fi
                ((ongoingpage++))
        done
        while read -r mal_id
        do
		if awk -F"\t" '{print $2}' $SCRIPT_FOLDER/override-ID-animes.tsv | grep -w  $mal_id
		then
			line=$(grep -w -n $mal_id $SCRIPT_FOLDER/override-ID-animes.tsv | cut -d : -f 1)
			tvdb_id=$(sed -n "${line}p" $SCRIPT_FOLDER/override-ID-animes.tsv | awk -F"\t" '{print $1}')
			title_mal=$(sed -n "${line}p" $SCRIPT_FOLDER/override-ID-animes.tsv | awk -F"\t" '{print $3}')
			printf "$tvdb_id\t$mal_id\t$title_mal\n" >> $SCRIPT_FOLDER/data/animes/ongoing.tsv
		else
			tvdb_id=$(get-tvdb-id)                                                                                  # convert the mal id to tvdb id (to get the main anime)
			if [[ "$tvdb_id" == 'null' ]] || [[ "${#tvdb_id}" == '0' ]]                                             # Ignore anime with no mal to tvdb id conversion
			then
				echo "Ongoing invalid TVDB ID for : MAL : $mal_id" >> $LOG
				continue
			else    												# get the mal ID again but main anime and create ongoing list
				mal_id=$(get-mal-id)
				if awk -F"\t" '{print $1}' $SCRIPT_FOLDER/override-ID-animes.tsv | grep -w  $tvdb_id
				then
					line=$(grep -w -n $tvdb_id $SCRIPT_FOLDER/override-ID-animes.tsv | cut -d : -f 1)
					mal_id=$(sed -n "${line}p" $SCRIPT_FOLDER/override-ID-animes.tsv | awk -F"\t" '{print $2}')
					title_mal=$(sed -n "${line}p" $SCRIPT_FOLDER/override-ID-animes.tsv | awk -F"\t" '{print $3}')
					printf "$tvdb_id\t$mal_id\t$title_mal\n" >> $SCRIPT_FOLDER/data/animes/ongoing.tsv
				elif [[ "$mal_title" == 'null' ]] || [[ "$mal_id" == 'null' ]] || [[ "${#mal_id}" == '0' ]]       # Ignore anime with no tvdb to mal id conversion show in the error log you need to add them by hand in override
				then
					echo "$(date +%Y.%m.%d" - "%H:%M:%S) - invalid MAL ID for Ongoing : tvdb : $tvdb_id" >> $LOG
					continue
				else
					get-mal-infos
					title_mal=$(get-mal-title)
					printf "$tvdb_id\t$mal_id\t$title_mal\n" >> $SCRIPT_FOLDER/data/animes/ongoing.tsv
				fi
			fi
		fi
        done < $SCRIPT_FOLDER/tmp/ongoing.tsv
fi

# write PMM metadata file from ID/animes.tsv and jikan API
while IFS=$'\t' read -r tvdb_id mal_id title_mal title_plex
do
	get-mal-infos
	echo "  \"$title_mal\":" >> $animes_titles
	echo "    alt_title: \"$title_plex\"" >> $animes_titles		
	echo "    sort_title: \"$title_mal\"" >> $animes_titles
	score_mal=$(get-mal-rating)
	echo "    audience_rating: $score_mal" >> $animes_titles				# rating (audience)
	mal_tags=$(get-mal-tags)
	echo "    genre.sync: Anime,${mal_tags}"  >> $animes_titles				# tags (genres, themes and demographics from MAL)
	if awk -F"\t" '{print "\""$3"\":"}' $SCRIPT_FOLDER/data/animes/ongoing.tsv | grep -w "\"$title_mal\":"		# Ongoing label according to MAL airing list
	then
		echo "    label: Ongoing" >> $animes_titles
		echo "$(date +%Y.%m.%d" - "%H:%M:%S) - $title_mal added to Ongoing" >> $LOG
	else
		echo "    label.remove: Ongoing" >> $animes_titles
		echo "$(date +%Y.%m.%d" - "%H:%M:%S) - $title_mal removed to Ongoing" >> $LOG
	fi
	mal_studios=$(get-mal-studios)
	echo "    studio: ${mal_studios}"  >> $animes_titles
	printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t$title_mal\tstudio : $mal_studios\n" >> $LOG
	get-mal-poster										# check / download poster
	echo "    file_poster: $SCRIPT_FOLDER/posters/${mal_id}.jpg" >> $animes_titles		# add poster 
	echo "$(date +%Y.%m.%d" - "%H:%M:%S) - added to metadata : $title_mal / score : $score_mal / tags / poster" >> $LOG
done < $SCRIPT_FOLDER/ID/animes.tsv