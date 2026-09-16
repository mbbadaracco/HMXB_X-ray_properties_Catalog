#!/bin/bash

logfile="Chandra_$(date +'%Y%m%d_%H%M%S').log" #echo both terminal and file
base_path="$PWD"
exec > >(tee -a "$logfile") 2>&1 # echo in terminal and in logfile
mkdir Chandra_files

# Initialize HEASoft and CIAO
heainit
ciaoinit

bands=(
  "200:500"
  "500:1000"
  "1000:2000"
  "2000:4500"
  "4500:10000"
  "300:10000"
)

run() {
        echo "Running: $*"  # Log the command
        "$@"
        }

echo -n "Do you want to download the data? (y/n): "
read -r answer
echo "User answered: $answer"

if [[ "$answer" == "y" ]]; then
        cd "$base_path/Chandra_files"
        echo "Chandra data will be stored in Chandra_files"
        # Download Chandra data of AX J1749.1-2733
        for obsid in 7504 9013; do
		run download_chandra_obsid "$obsid"
	done
	cd "$base_path"
	echo "Done with data downloading."
fi

# Reprocessing
echo -n "Do you want to reprocess the data? (y/n): "
read -r answer2
echo "User answered: $answer2"

if [[ "$answer2" == "y" ]]; then
	echo "Beginning reprocessing of Chandra data..."
	echo "The reprocessed data of 'obsid' Chandra observation will be stored in Chandra_files/obsid_repro"
	cd Chandra_files
	for obsid in 7504 9013; do
		run chandra_repro indir="$obsid" outdir="${obsid}_repro" clobber=yes
	done
	cd "$base_path"
	echo "Done with reprocessing Chandra data."
fi

# Images
echo -n "Do you want to generate the images? (y/n): "
read -r answer3
echo "User answered: $answer3"
if [[ "$answer3" == "y" ]]; then
	echo "Generating Chandra images..."
	cd Chandra_files
	for obsid in 7504 9013; do
		cd ${obsid}_repro
		target_filename=$(ls *repro_evt2.fits)
		for i in "${!bands[@]}"; do
			band_index=$((i+1))
			energy_range=${bands[$i]}
			run dmcopy "${target_filename}[events][energy=${energy_range}][bin x=::4,y=::4][IMAGE]" "${target_filename%repro_evt2.fits}$band${band_index}_img.fits" clobber=yes
		done
		cd ..
	done
	cd "$base_path"
	echo "Done generating Chandra images."
fi

echo -n "Do you want to detect sources? (y/n): "
read -r answer4
if [[ "$answer4" == "y" ]]; then
	echo "Detecting sources in Chandra observations..."
	cd Chandra_files
	for obsid in 7504 9013; do
		cd ${obsid}_repro
			for i in "${!bands[@]}"; do
				band_index=$((i+1))
				target_filename=$(ls *band${band_index}_img.fits)
				energy_range=${bands[$i]}
				run mkpsfmap "${target_filename}" "${target_filename%band${band_index}_img.fits}band${band_index}_psfmap.fits" energy=1.49 ecf=0.393 clobber=yes
				run wavdetect "${target_filename}" "${target_filename%band${band_index}_img.fits}band${band_index}_source_list.fits" "${target_filename%band${band_index}_img.fits}band${band_index}_source_cell.fits" "${target_filename%band${band_index}_img.fits}band${band_index}_image.fits" "${target_filename%band${band_index}_img.fits}band${band_index}_bkg.fits" expfile=none psffile="${target_filename%band${band_index}_img.fits}band${band_index}_psfmap.fits" clobber=yes
			done
		cd ..
	done
	cd "$base_path"
	echo "Done with detection of sources in Chandra observations."
	
fi



