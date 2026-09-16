#!/bin/bash

logfile="EPIC_$(date +'%Y%m%d_%H%M%S').log"
base_path="$PWD"
exec > >(tee -a "$logfile") 2>&1 # echo in terminal and in logfile

mkdir EPIC_files
cd EPIC_files
mkdir data
mkdir analysis
cd ..

# Initialize HEASoft and SAS
heainit
sasinit
sas_ccfpath="/home/marina/Software/SAS/CCF"
echo "Default SAS_CCFPATH is '/home/marina/Software/SAS/CCF'"
echo -n "Insert 1 for default, 2 for customized path: "
read -r answer

if [[ "$answer" == "1" ]]; then
	export SAS_CCFPATH="$sas_ccfpath"
elif [[ "$answer" == "2" ]]; then
	echo -n "Enter custom SAS_CCFPATH: "
	read -r sas_ccfpath_customized
	export SAS_CCFPATH="$sas_ccfpath_customized"
fi
echo "SAS_CCFPATH set to: $SAS_CCFPATH"

cameras=("EMOS1" "EMOS2" "EPN")
bands=(
  "200:500"
  "500:1000"
  "1000:2000"
  "2000:4500"
  "4500:12000"
  "300:10000"
)
bin_size=80 #this ensures that 4arcsec=1pixel

run() {
        echo "Running: $*"  # Log the command
        "$@"
        }

echo -n "Do you want to download the data? (y/n): "
read -r answer2
echo "User answered: $answer2"

if [[ "$answer2" == "y" ]]; then
        echo "EPIC data will be stored in EPIC_files/data"
	# Download XMM-Newton data of AX J1749.1-2733
	cd EPIC_files/data
	for obsid in 0510010401 0511010301; do
		mkdir "$obsid"
        	cd "$obsid" 
        	run curl -o "${obsid}.tar" "https://nxsa.esac.esa.int/nxsa-sl/servlet/data-action-aio?obsno=${obsid}&level=ODF"
        	run tar -xvf "${obsid}.tar"
        	run tar -xvf *"${obsid}".TAR
        	cd ..
        done
        echo "Done with data downloading."
fi
cd ..

# Reprocessing
echo -n "Do you want to reprocess the data? (y/n): "
read -r answer3
echo "User answered: $answer3"
if [[ "$answer3" == "y" ]]; then
	echo "Beginning reprocessing of XMM-Newton data..."
	echo "The reprocessed data of EPIC observations will be stored in EPIC_files/analysis"
	cd $base_path/EPIC_files/analysis
	for obsid in 0510010401 0511010301; do
		mkdir "$obsid"
		cd "$obsid"
		export SAS_ODF="$base_path/EPIC_files/data/${obsid}"
		cifbuild
		export SAS_CCF="$base_path/EPIC_files/analysis/${obsid}/ccf.cif"
		odfingest
		target_sas=$(ls *SUM.SAS)
		export SAS_ODF="$base_path/EPIC_files/analysis/${obsid}/$target_sas"
		emproc
		epproc  
		cd ..
	done
	cd "$base_path"

	echo "Done with reprocessing XMM-Newton data."
fi

#Background correction and PATTERN filtering
echo -n "Do you want to correct for Good Time Intervals (GTI) and PATTERN? (y/n): "
read -r answer3_bis
echo "User answered: $answer3_bis"
if [[ "$answer3_bis" == "y" ]]; then
	echo "Correcting EPIC observations for GTI and PATTERN..."
	# Cameras to process
	expression1_mos='#XMMEA_EM && (PI>10000) && (PATTERN==0)'
	expression1_pn='#XMMEA_EP && (PI>10000 && PI<12000) && (PATTERN==0)'
	expression2_mos1='#XMMEA_EM && gti(EMOS1gti.fits,TIME) && (PI>=200.0 && PI<=12000.0 && PATTERN<=12)'
        expression2_mos2='#XMMEA_EM && gti(EMOS2gti.fits,TIME) && (PI>=200.0 && PI<=12000.0 && PATTERN<=12)'
        expression2_pn='#XMMEA_EP && gti(EPNgti.fits,TIME) && ((PI>=200.0 && PI<=500.0 && PATTERN==0) || (PI>500.0 && PI<=12000.0 && PATTERN<=4)) && (FLAG==0)'
	cd $base_path/EPIC_files/analysis
	for obsid in 0510010401 0511010301; do
		cd "$obsid"
		export SAS_CCF="$base_path/EPIC_files/analysis/${obsid}/ccf.cif"
		target_sas=$(ls *SUM.SAS)
		export SAS_ODF="$base_path/EPIC_files/analysis/${obsid}/$target_sas"
		for cam in "${cameras[@]}"; do
			for infile in *"${cam}"*Evts.ds; do
				if [[ "$cam" == "EPN" ]]; then
					expression1="$expression1_pn"
					expression2="$expression2_pn"
					if [[ $obsid == "0510010401" ]]; then
						threshold="0.5"
					else
						threshold="0.6"
					fi
				elif [[ "$cam" == "EMOS1" ]]; then
					expression1="$expression1_mos"
					expression2="$expression2_mos1"
					if [[ $obsid == "0510010401" ]]; then
						threshold="0.25"
					else
						threshold="0.35"
					fi
				else
					expression1="$expression1_mos"
					expression2="$expression2_mos2"
					if [[ $obsid == "0510010401" ]]; then
						threshold="0.22"
					else
						threshold="0.35"
					fi
				fi
				run evselect table="$infile" withrateset=Y rateset="rate${cam}.fits" maketimecolumn=Y timebinsize=100 makeratecolumn=Y expression="$expression1"
				run tabgtigen table="rate${cam}.fits" expression="RATE<=$threshold" gtiset="${cam}gti.fits"
				run evselect table="$infile" withfilteredset=Y filteredset="${cam}clean.fits" destruct=Y keepfilteroutput=T expression="$expression2"
				run fkeyprint "$infile"[1] LIVETIME
				run fkeyprint ${cam}clean.fits[1] LIVETIME
			done
		done
		cd ..
	done
	echo "Done correcting EPIC observations for GTI and PATTERN."
fi
cd $base_path

# Images
echo -n "Do you want to generate the images? (y/n): "
read -r answer4
echo "User answered: $answer4"
if [[ "$answer4" == "y" ]]; then
	cd EPIC_files/analysis
	echo "Beginning generation of images..."
	for obsid in 0510010401 0511010301; do
		cd $obsid
		export SAS_CCF=$base_path/EPIC_files/analysis/${obsid}/ccf.cif
		target_sas=$(ls $base_path/EPIC_files/analysis/$obsid/*SUM.SAS)
		export SAS_ODF=$base_path/EPIC_files/analysis/${obsid}/$target_sas

		for cam in "${cameras[@]}"; do
			for i in "${!bands[@]}"; do
				band_index=$((i+1))
			    	energy_range=${bands[$i]}
			    	run evselect table="${cam}clean.fits" xcolumn=X ycolumn=Y imagebinning=binSize ximagebinsize=$bin_size yimagebinsize=$bin_size withimageset=true imageset="${cam}_image_band${band_index}.fits" expression="(PI in [${energy_range}])"
			done
		done
		cd ..
	done
	echo "Done generating EPIC images."
fi
cd $base_path

echo -n "Do you want to detect sources? (y/n): "
read -r answer5
if [[ "$answer5" == "y" ]]; then
	cd EPIC_files/analysis
	echo "Detecting sources in EPIC observations..."
	for obsid in 0510010401 0511010301; do
		cd $obsid
		export SAS_CCF=$base_path/EPIC_files/analysis/${obsid}/ccf.cif
		target_sas=$(ls *SUM.SAS)
		export SAS_ODF=$base_path/EPIC_files/analysis/${obsid}/$target_sas
		if [[ "$obsid" == "0510010401" ]]; then
			att_file="1338_0510010401_AttHk.ds"
		else
			att_file="1508_0511010301_AttHk.ds"
		fi
		run edetect_chain imagesets='EPN_image_band1.fits EPN_image_band2.fits EPN_image_band3.fits EPN_image_band4.fits EPN_image_band5.fits EMOS1_image_band1.fits EMOS1_image_band2.fits EMOS1_image_band3.fits EMOS1_image_band4.fits EMOS1_image_band5.fits EMOS2_image_band1.fits EMOS2_image_band2.fits EMOS2_image_band3.fits EMOS2_image_band4.fits EMOS2_image_band5.fits' eventsets='EPNclean.fits EMOS1clean.fits EMOS2clean.fits' attitudeset="${att_file}" pimin='200 500 1000 2000 4500 200 500 1000 2000 4500 200 500 1000 2000 4500' pimax='500 1000 2000 4500 12000 500 1000 2000 4500 12000 500 1000 2000 4500 12000' ecf='8.37 7.87 5.77 1.93 0.58 1.53 1.70 2.01 0.73 0.15 1.52 1.71 2.01 0.73 0.15' eboxl_list='allcameras_eboxlist_l.fits' eboxm_list='allcameras_eboxlist_m.fits' eml_list='allcameras_emllist.fits' esp_nsplinenodes=16 esen_mlmin=15 eml_ecut=0.68 eml_scut=0.9 eml_fitextent=yes psfmodel=ellbeta
		cd ..
	done
	echo "Done with detection of sources in EPIC observations."
	cd $base_path
fi




