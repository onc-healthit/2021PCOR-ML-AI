library(RPostgres)
library(DBI)
library(readr)
library(dplyr)
library(lubridate)
library(stringr)
source('CreateDataSet/S0-connectToPostgres.R')
source('CreateDataSet/pre_esrd_pre2011_claim_variables.R')

#Before 2011, pre-ESRD claims are stored in the files inc2008.csv, inc2009.csv, inc2010.csv. The files are organized differently from the other pre-esrd files: the type of claim is not part of the file name (instead, it is identified in the file's contents in a field called "hcfasaf"); and the contents of the file can differ from year to year. Also, the pdgns_cd is not available prior to 2012. This script constructs a pdgns_cd from the drg_cd which is available prior to 2011.	
# Step1: Import the pre-2011 claims and filter on usrds_ids in the cohort and features in the post2011 claims.
# 	Set cdtype = "I" to indicae icd9, 
# 	set any missing drg_cd=000.
# 
# Step 2: For each Claim type (hh, hs, ip, sn, op)
# 	Generate a uniform random number for each record in pre2011 claims, 
# 	and look up pdgns_cd from drg_cd_mapping based on this random number, 
# 	which will produce a pdgns_cd reflecting the underlying
#         joint distribution of (drg_cd,pdgns_cd) in the data
#  
# Step 3: Insert these rows into the main postgres table for this claim type
# 
# - Input: inc2008.csv, inc2009.csv, inc2010.csv; the postgresql table `drg_cd_mapping`, pre_esrd_pre2011_claim_variables.R
# - Output: Rows of pre-2011 claims for the cohort added to the following postgresql tables 	
# 
# preesrd5y_ip_clm_inc
# preesrd5y_hh_clm_inc
# preesrd5y_hs_clm_inc
# preesrd5y_op_clm_inc
# preesrd5y_sn_clm_inc

data_dir = file.path("data")

# Script Function definitions -----------------------------------------------------
create_pre_2011 <- function(
    data_dir, 
    filename, 
    tblname,
    append_flag,
    table_name_pt, 
    newIn2010, 
    column_types){
    
    inc20xx = read_csv(file.path(data_dir, str_glue("{filename}.csv")), col_types=column_types)
    incident_year =
        substr(filename, str_length(filename) - 3, str_length(filename))
    names(inc20xx) = tolower(names(inc20xx))
    
    patients = dbGetQuery(
        con,
        str_glue(
            "SELECT usrds_id
            FROM {table_name_pt}")
    )
    
    # filter on ids from the patient table
    inc20xx = inc20xx %>% 
        filter(
            usrds_id %in% patients$usrds_id) %>%
        mutate(
            incident_year = incident_year,
            cdtype = "I",
            drg_cd = ifelse(
                    is.na(drg_cd), "000", drg_cd),
            drg_cd = ifelse(
                    drg_cd == "", "000", drg_cd)) %>%
        mutate(
            drg_cd = as.numeric(drg_cd))
    
    sortednm = names(inc20xx) %>% sort()
    inc20xx = inc20xx[, sortednm]
    
    if (append_flag==FALSE){
        inc20xx[, newIn2010] = NA
        drop_table_function(con, tblname)
    }
    print(nrow(inc20xx))
    dbWriteTable(
        con,
        tblname, 
        inc20xx, 
        append = append_flag,
        row.names = FALSE)
}
get_claim_type_x <- function(claim_type, table_nm) {
    print(str_glue("get {claim_type}"))
    df = dbGetQuery(
        con,
        str_glue(
            "
            SELECT * 
            FROM {table_nm} 
            WHERE hcfasaf='{claim_type}'
            "))
    return(df)
}
get_distribution <- function(df){
    # Generate a uniform rv for each record in df, and look up pdgns_cd from drg_cd_mapping
    # based on this rv, which will produce a pdgns_cd reflecting the underlying
    # joint distribution of (drg_cd,pdgns_cd) in the data
    
    print("get distribution of drg_cd, pdgns_cd")
    set.seed(597)
    
    df$rv = runif(
        dim(df)[1]
        )
    temptablename = "temp_df"
    
    drop_table_function(con, temptablename)
    
    dbWriteTable(
        con, 
        temptablename,
        df,
        temporary = TRUE
    )
    dg = dbGetQuery(
        con,
        str_glue(
            "
            SELECT a.*, b.pdgns_cd 
            FROM {temptablename} a 
                LEFT JOIN drg_cd_mapping b 
                ON a.drg_cd = b.drg_cd 
                AND a.rv <= b.ub 
                AND a.rv > b.lb
            "))
    return(dg)
}
insert_claim_rows <- function(claim_type, pre2011_data) {
    #Get the field names to be inserted into the pre-esrd data, 
    # in the correct order
    print(str_glue("intert pre 2011 {claim_type} rows into table {nrow(pre2011_data)}"))
    main_fieldnames = names(
        dbGetQuery(
            con, 
            str_glue(
                "
                SELECT * 
                FROM preesrd5y_{claim_type}_clm_inc
                LIMIT 10
                ")
            )
    )
    
    #Set fields in main claims fieldnames that do not appear in the pre2011 data = nan
    pre2011_data[, setdiff(main_fieldnames, names(pre2011_data))] = NA
   
    # Include only fields also in main_fieldnames, in the proper order
    pre2011_data = pre2011_data[, main_fieldnames]
    
    # append pre2011 rows to the main claims table
    main_tblname = str_glue("preesrd5y_{claim_type}_clm_inc")
    dbWriteTable(
        con, 
        main_tblname, 
        pre2011_data, 
        append = TRUE, 
        row.names = FALSE)
    }
source_pre_2011 <- function(data_dir, tblname, column_types) {

    newIn2010 = c(
        "dpoadmin",
        "dpodose",
        "hgb",
        "dpocash",
        "attending_phys",
        "operating_phys",
        "other_phys"
    )

    create_pre_2011(data_dir, 
                    "inc2010", 
                    tblname, 
                    append_flag=FALSE, 
                    table_name_pt = "patients_medevid_waitlist",
                    newIn2010, 
                    column_types)
    
    create_pre_2011(data_dir, 
                    "inc2009", 
                    tblname, 
                    append_flag=TRUE, 
                    table_name_pt = "patients_medevid_waitlist",
                    newIn2010, 
                    column_types)
    
    create_pre_2011(data_dir,
                    "inc2008",
                    tblname,
                    append_flag=TRUE, 
                    table_name_pt = "patients_medevid_waitlist",
                    newIn2010, 
                    column_types)

    ########BEGIN HOME HEALTH#######
    df = get_claim_type_x("H",tblname)
    dg = get_distribution(df)
    insert_claim_rows("hh", dg)
    rm(df,dg)
    
    ####BEGIN HOSPICE##########
    df = get_claim_type_x("S", tblname)
    dg = get_distribution(df)
    insert_claim_rows("hs", dg)
    rm(df,dg)
    
    ####BEGIN INPATIENT#######
    df = get_claim_type_x("I", tblname)
    dg = get_distribution(df)
    insert_claim_rows("ip", dg)
    rm(df,dg)
    
    ###BEGIN SKILLED NURSING####
    df = get_claim_type_x("N", tblname)
    dg = get_distribution(df)
    insert_claim_rows("sn", dg)
    rm(df,dg)
    
    ####BEGIN OUTPATIENT####
    df = get_claim_type_x("O", tblname)

    # Step 2: Generate a uniform rv for each record in df, and look up pdgns_cd from drg_cd_mapping
    # based on this rv, which will produce a pdgns_cd reflecting the underlying
    # joint distribution of (drg_cd, pdgns_cd) in the data
    set.seed(597)
    df$rv = runif(
        dim(df)[1]
        )
    temptablename = "temp_df"
    drop_table_function(con, temptablename)
    dbWriteTable(
        con,
        temptablename, 
        df, 
        temporary = TRUE
        )

    make_query <- function(dg_vals, temptablename){
        dg = str_glue(
                "WITH w as (
                            SELECT * 
                            FROM {temptablename}
                            WHERE MOD(CAST(usrds_id AS NUMERIC),10) IN ({dg_vals})
                            )
                SELECT a.*, b.pdgns_cd 
                FROM w a 
                LEFT JOIN drg_cd_mapping b
                    ON a.drg_cd = b.drg_cd 
                    AND a.rv <= b.ub 
                    AND a.rv > b.lb"
        )
        return(dg)
    }
    dg_1 = dbGetQuery(con, make_query("0,1", temptablename))
    
    dg_2 = dbGetQuery(con, make_query("2,3", temptablename))
    
    dg_3 = dbGetQuery(con, make_query("4,5", temptablename))
                      
    dg_4 = dbGetQuery(con, make_query("6,7", temptablename))

    dg_5 = dbGetQuery(con, make_query("8,9", temptablename))

    dg = rbind(dg_1, dg_2)
    dg = dg %>% 
        rbind(dg_3) %>% 
        rbind(dg_4) %>% 
        rbind(dg_5)

    #step 3 append rows to main table
    insert_claim_rows("op", dg)
}
# Execute function --------------------------------------------------------
source_pre_2011(data_dir,"pre_esrd_2011", columns_esrd_2015)
