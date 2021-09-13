library(readr)
library(haven)
library(stringr)
# Script Function definition -----------------------------------------------------
#' Title \code{convert_to_csv} Convert and combine raw source data from sas files
#' to .csv files
#' @param source_data_dir string path to the raw data file
#' @param file_name string name of the file without the extension
#' @param output_data_dir string path to the output directory for csv files
#' @export a .csv version of the file with the same file_name
#'
#' @examples \code{convert_to_csv("/home/sas_data_usrds/, "patients", "/home/csv_data_usrds/)}
#' 
#' 
convert_to_csv = function(source_data_dir, file_name, output_data_dir) {
  raw_file_path = haven::read_sas(str_glue("{source_data_dir}{file_name}.sas7bdat"))
  csv_path = str_glue("{output_data_dir}{file_name}.csv")
  write_csv(raw_file_path, csv_path)
}
# Execute function --------------------------------------------------------
file_list = c(
  "ckd_patient_master_file",
  "death",
  "inc2008",
  "inc2009",
  "inc2010",
  "medevid",
  "patients",
  "tx",
  "waitseq_ki",
  "waitseq_kp",
  "preesrd5y_hh_clm_inc2012",
  "preesrd5y_hh_clm_inc2013",
  "preesrd5y_hh_clm_inc2014",
  "preesrd5y_hh_clm_inc2015",
  "preesrd5y_hh_clm_inc2016",
  "preesrd5y_hh_clm_inc2017",
  "preesrd5y_hh_clm_inc2011",
  "preesrd5y_hs_clm_inc2012",
  "preesrd5y_hs_clm_inc2013",
  "preesrd5y_hs_clm_inc2014",
  "preesrd5y_hs_clm_inc2015",
  "preesrd5y_hs_clm_inc2016",
  "preesrd5y_hs_clm_inc2017",
  "preesrd5y_hs_clm_inc2011",
  "preesrd5y_ip_clm_inc2012",
  "preesrd5y_ip_clm_inc2013",
  "preesrd5y_ip_clm_inc2014",
  "preesrd5y_ip_clm_inc2015",
  "preesrd5y_ip_clm_inc2016",
  "preesrd5y_ip_clm_inc2017",
  "preesrd5y_ip_clm_inc2011",
  "preesrd5y_hh_clm_inc2011",
  "preesrd5y_sn_clm_inc2012",
  "preesrd5y_sn_clm_inc2013",
  "preesrd5y_sn_clm_inc2014",
  "preesrd5y_sn_clm_inc2015",
  "preesrd5y_sn_clm_inc2016",
  "preesrd5y_sn_clm_inc2017",
  "preesrd5y_sn_clm_inc2011",
  "preesrd5y_op_clm_inc2012",
  "preesrd5y_op_clm_inc2013",
  "preesrd5y_op_clm_inc2014",
  "preesrd5y_op_clm_inc2015",
  "preesrd5y_op_clm_inc2016",
  "preesrd5y_op_clm_inc2017",
  "preesrd5y_op_clm_inc2011"
)

dir_to_files = file.path("", "data_raw", "")
dir_for_csv = file.path("", "data", "")

for (file_nm in file_list) {
  convert_to_csv(dir_to_files, file_nm, dir_for_csv)
}