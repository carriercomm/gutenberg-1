#!/bin/bash

# Colors
ESC_SEQ="\x1b["
COL_RESET=$ESC_SEQ"39;49;00m"
COL_RED=$ESC_SEQ"31;01m"
COL_GREEN=$ESC_SEQ"32;01m"
COL_YELLOW=$ESC_SEQ"33;01m"
COL_BLUE=$ESC_SEQ"34;01m"
COL_MAGENTA=$ESC_SEQ"35;01m"
COL_CYAN=$ESC_SEQ"36;01m"


source $(dirname $(readlink -e shell-script))/blueprint.sh

function in_vault {
  if [[ $(pwd) =~ /vault/ ]] ; then 
    echo true
  else
    echo false
  fi
}

function get_bank_path {
  if [ -e /opt/gutenberg/PRODUCTION_SERVER ] ; then
    echo "/home/gutenberg/bank"
  else
    if [ -z $BANK ]  ; then
      b=$(grep -m 1 bank /opt/gutenberg/config | sed -e 's/bank: //')
      echo $b
    else
      echo $BANK
    fi
  fi
}

function create_skeleton {
  # TeX files are created in many contexts - but always in the following order
  # question -> quiz -> worksheet -> exam
  # The TeX for each stage requires TeX from the immediately preceding stage. 
  # The skel file is the TeX from the preceding stage that can be 
  # blindly copied / concatenated to create the TeX for this stage 

  if [ -e skel ] ; then rm -f skel ; fi
  import=$(get_import_folders)
  mode=$(get_mode)
  bank=$(get_bank_path)


  if [ $mode == "vault" -o $mode == "quiz" ] ; then 
    src="vault"
    file="question.tex"
  else
    src="mint"
    file="skel"
  fi

  for f in $import ; do
    p=$src/$f
    echo "... [importing]: $p"
    cat -s $bank/$p/$file >> skel
  done
  clean_tex skel 

  # Add details to skel as needed depending on $mode
  if [ $mode == "quiz" ] ; then 
    open_questions skel
    sed -i "1i \\\\\\setDocumentTitle{$(get_title)}" skel 
    sed -i "1i \\\\\\setPageBreaks{$(get_page_breaks)}" skel 
  else
    if [ $mode == "worksheet" ] ; then 
      sed -i "1i \\\\\\setAuthor[$(get_versions)]{$(get_author)}{$(get_response_ids)}" skel 
      sed -i "1i \\\\\\noprintanswers" skel
    fi
  fi 
}


function create_tex_from_skel { 
  mode=$(get_mode)
  bank=$(get_bank_path)

  if [ -z $1 ] ; then file=preview.tex ; else file=$1 ; fi
  cat -s skel > $file

  if [ $mode == "vault" ] ; then open_questions $file ; fi
  open_document $file
  if [ $mode == "vault" ] ; then 
    sed -i "1i \\\\\\setDocumentTitle{Question Preview}" $file
    sed -i "1i \\\\\\setAuthor[]{Gradians.com}{}" $file
    sed -i "1i \\\\\\printanswers" $file
  else 
    if [ $mode == "quiz" ] ; then 
      sed -i "1i \\\\\\printanswers" $file
      sed -i "1i \\\\\\setAuthor[]{$(get_author)}{}" $file
    fi
  fi

  open_file $file
}

function open_questions {
  sed -i "1i \\\\\\begin{questions}" $1 
  sed -i "$ a \\\\\\end{questions}" $1 
}

function open_document { 
  sed -i "1i \\\\\\begin{document}" $1
  sed -i "$ a \\\\\\end{document}" $1
}

function open_file {
  # Note that TeX is being written in the reverse order
  sed -i "1i \\\\\\fancyfoot[C]{\\\\copyright\\,Gradians.com}" $1
  sed -i "1i \\\\\\documentclass[12pt,a4paper,justified]{tufte-exam}" $1
}

function set_cancelspace {
  # $1 = Target TeX File
  sed -i '4i \\\cancelspace' $1
}

function unset_cancelspace { 
  # $1 = Target TeX File
  line=$(grep -m 1 -n '\\cancelspace' $1 | head -1 | sed -e 's/:.*//')
  if [ $line ] ; then
    sed -i "$line d" $1
  fi
} 


### Vault Specific

function create_blueprint_in_vault {
  if [ -e blueprint ] ; then return 0 ; fi
  rel_path=$(pwd | sed -e 's/.*\/vault\///')

  echo "author: Gradians.com" >> blueprint
  echo "title: Question Preview" >> blueprint
  echo "mode: vault" >> blueprint 
  echo "import: $rel_path" >> blueprint
}

function set_question_version {
  # $1 = Target TeX file 
  # $2 = version - a number in [0,3]

  line=$(grep -m 1 -n 'setAuthor' $1 | sed -e 's/:.*//')
  if [ $line ] ; then 
    sed -i -e "$line s/setAuthor\[.*\]/setAuthor[$2]/" $1
  fi
}

function compile_question_tex {
  # $1 = Source TeX file
  # $2 = Log file (optional)

  base=$(ls $1 | sed -e 's/\..*//') # preview.tex -> preview | abhinav.tex -> abhinav
  mode=$(get_mode)

  latex -halt-on-error $base.tex
  if [ -e $base.dvi ] ; then 
    dvips -q $base.dvi
    if [ -e $base.ps ] ; then 
      ps2pdf $base.ps
      if [ -e $base.pdf -a $mode == "vault" ] ; then 
        gs -dNOPAUSE -dBATCH -sDEVICE=jpeg -r700 -sOutputFile=pg-%d.jpg $base.pdf
        for f in `ls pg-*.jpg` ; do convert $f -resize 600x800 $f ; done
      else
        if [ ! -z $2 ] ; then echo ".... [ps -> pdf] -> failed" >> $2 ; fi
      fi
    else
      if [ ! -z $2 ] ; then echo ".... [dvi -> ps] -> failed" >> $2 ; fi
    fi
  else
    if [ ! -z $2 ] ; then echo ".... [TeX -> dvi] -> failed" >> $2 ; fi
  fi
}

function clean_tex {
  # 1. Remove any LaTeX comments 
  sed -i '/^%/d' $1

  # 2.  Remove any unused \renewcommand\vb* variables
  b=$(grep -m 1 -n "rolldice" $1 | sed -e 's/:.*//')
  e=$(grep -m 1 -n "\\\\question" $1 | sed -e 's/:.*//')

  sed -i -e '/renewcommand.*{}/d' $1
}
