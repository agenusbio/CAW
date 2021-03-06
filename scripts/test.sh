#!/bin/bash
set -xeuo pipefail

GENOME=smallGRCh37
PROFILE=singularity
SAMPLE=data/tsv/tiny.tsv
TEST=ALL
TRAVIS=${TRAVIS:-false}
BUILD=false

while [[ $# -gt 0 ]]
do
  key=$1
  case $key in
    -g|--genome)
    GENOME=$2
    shift # past argument
    shift # past value
    ;;
    -p|--profile)
    PROFILE=$2
    shift # past argument
    shift # past value
    ;;
    -s|--sample)
    SAMPLE=$2
    shift # past argument
    shift # past value
    ;;
    -t|--test)
    TEST=$2
    shift # past argument
    shift # past value
    ;;
    -b|--build)
    BUILD=true
    shift # past value
    ;;
    *) # unknown option
    shift # past argument
    ;;
  esac
done

function nf_test() {
  echo "$(tput setaf 1)nextflow run $@ -profile $PROFILE --genome $GENOME -resume --verbose$(tput sgr0)"
  nextflow run $@ -profile $PROFILE --genome $GENOME -resume --genome_base $PWD/References/$GENOME --verbose
}

# Build references only for smallGRCh37
if [[ $GENOME == smallGRCh37 ]] && [[ $TEST != BUILDCONTAINERS ]] && [[ BUILD ]]
then
  nf_test buildReferences.nf --download --outDir References/$GENOME
  # Remove images only on TRAVIS
  if [[ $PROFILE == docker ]] && [[ $TRAVIS == true ]]
  then
    docker rmi -f maxulysse/igvtools:latest
  elif [[ $PROFILE == singularity ]] && [[ $TRAVIS == true ]]
  then
    rm -rf work/singularity/igvtools-latest.img
  fi
fi

if [[ ALL,MAPPING,ONLYQC,REALIGN,RECALIBRATE =~ $TEST ]]
then
  nf_test . --step mapping --sampleDir data/tiny/tiny/normal
  nf_test . --step mapping --sample $SAMPLE
fi

if [[ ALL,ONLYQC =~ $TEST ]]
then
  nf_test . --step mapping --sample $SAMPLE --tools Strelka --noReports
  nf_test . --step variantCalling --tools Strelka --onlyQC
fi

if [[ ALL,REALIGN =~ $TEST ]]
then
  nf_test . --step realign --noReports
  nf_test . --step realign --tools HaplotypeCaller
  nf_test . --step realign --tools HaplotypeCaller --noReports --noGVCF
fi

if [[ ALL,RECALIBRATE =~ $TEST ]]
then
  nf_test . --step recalibrate --noReports
  nf_test . --step recalibrate --tools FreeBayes,HaplotypeCaller,MuTect1,MuTect2,Strelka
  # Test whether restarting from an already recalibrated BAM works
  nf_test . --step variantCalling --tools Strelka --noReports
fi

if [[ ALL,ANNOTATESNPEFF,ANNOTATEVEP =~ $TEST ]]
then
  if [[ $TEST = ANNOTATESNPEFF ]]
  then
    ANNOTATOR=snpEFF
  elif [[ $TEST = ANNOTATEVEP ]]
  then
    ANNOTATOR=VEP
  elif  [[ $TEST = ALL ]]
  then
    ANNOTATOR=snpEFF,VEP
  fi
  if [[ $PROFILE == docker ]] && [[ $TRAVIS == true ]]
  then
    docker rmi -f maxulysse/caw:latest
    docker rmi -f maxulysse/picard:latest
  elif [[ $PROFILE == singularity ]] && [[ $TRAVIS == true ]]
  then
    rm -rf work/singularity/caw-latest.img
    rm -rf work/singularity/picard-latest.img
  fi
  nf_test . --step annotate --tools ${ANNOTATOR} --annotateVCF data/tiny/vcf/Strelka_1234N_variants.vcf.gz --noReports
  nf_test . --step annotate --tools ${ANNOTATOR} --annotateVCF data/tiny/vcf/Strelka_1234N_variants.vcf.gz,data/tiny/vcf/Strelka_9876T_variants.vcf.gz --noReports
fi

if [[ ALL,BUILDCONTAINERS =~ $TEST ]] && [[ $PROFILE == docker ]]
then
  nf_test buildContainers.nf --docker --containers caw,fastqc,gatk,igvtools,multiqc,mutect1,picard,qualimap,runallelecount,r-base,snpeff
fi
