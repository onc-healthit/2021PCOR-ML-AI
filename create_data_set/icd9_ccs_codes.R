# ICD9 codes from CCS
#Utility file: Used by the script *dxCodeGrouping.R* to produce the table `dxMap`
#Group codes related to alcohol abuse, drug abuse, pulmonary disorders, 
#and renal failure based on the Clinical classification system (CCS) rules for grouping ICD9 diagnosis codes. 
# https://www.hcup-us.ahrq.gov/toolssoftware/ccs/ccs.jsp#download

library(tidyr)
library(stringr)

# pneumonia codes
line1 = "00322 0203 0204 0205 0212 0221 0310 0391 0521 0551 0730 0830"
line2 = "1124 1140 1144 1145 11505 11515 11595 1304 1363 4800 4801 4802"
line3 = "4803 4808 4809 481 4820 4821 4822 4823 48230 48231 48232 48239"
line4 = "4824 48240 48241 48242 48249 4828 48281 48282 48283 48284 48289"
line5 = "4829 483 4830 4831 4838 4841 4843 4845 4846 4847 4848 485 486 5130 5171"

# copd codes
line6 = "490 4910 4911 4912 49120 49121 49122 4918 4919 4920 4928 494 4940 4941 496"
pne_9 = paste0(line1, " ", line2, " ", line3, " ", line4, " ", line5, " ", line6) %>%
  strsplit(split = " ") %>% unlist()

#smoking codes
line1 = "V1582 98984 3051"

smo_9 = line1 %>% strsplit(split = " ") %>% unlist()

#substance abuse codes
line1 = "2920 29211 29212 2922 29281 29282 29283 29284 29285 29289 2929"
line2 = "30400 30401 30402 30403 30410 30411 30412 30413 30420 30421 30422"
line3 = "30423 30430 30431 30432 30433 30440 30441 30442 30443 30450 30451"
line4 = "30452 30453 30460 30461 30462 30463 30470 30471 30472 30473 30480"
line5 = "30481 30482 30483 30490 30491 30492 30493 30520 30521 30522 30523"
line6 = "30530 30531 30532 30533 30540 30541 30542 30543 30550 30551 30552 30553"
line7 = "30560 30561 30562 30563 30570 30571 30572 30573 30580 30581 30582 30583 30590"
line8 = "30591 30592 30593 64830 64831 64832 64833 64834 65550 65551 65553 76072 76073"
line9 = "76075 7795 96500 96501 96502 96509 V6542"
drg_9 = paste0(line1,
         " ",
         line2,
         " ",
         line3,
         " ",
         line4,
         " ",
         line5,
         " ",
         line6,
         " ",
         line7,
         " ",
         line8,
         " ",
         line9) %>% strsplit(split = " ") %>% unlist()

#alcohol-related disorders
line1 = "2910 2911 2912 2913 2914 2915 2918 29181 29182 29189 2919 30300 30301 30302"
line2 = "30303 30390 30391 30392 30393 30500 30501 30502 30503 3575 4255 5353 53530 53531"
line3 = "5710 5711 5712 5713 76071 9800"
alc_9 = paste0(line1, " ", line2, " ", line3) %>% strsplit(split = " ") %>% unlist()

#renal-failure codes
line1 = "5845 5846 5847 5848 5849 586"
kid_9 = line1 %>% strsplit(split = " ") %>% unlist()


##############
jnk = dbGetQuery(
  con,
  "SELECT pdgns_cd, count(*) AS nmbr 
   FROM preesrd5y_op_clm_inc
   WHERE cdtype='I' group BY pdgns_cd"
)

names(jnk)
jnk = jnk %>% mutate(flag = (pdgns_cd %in% smo_9))

alc_9 = alc_9 %>%
  str_pad(.,
          width = 7,
          side = "right",
          pad = "0")

drg_9 = drg_9 %>%
  str_pad(.,
          width = 7,
          side = "right",
          pad = "0")

kid_9 = kid_9 %>%
  str_pad(.,
          width = 7,
          side = "right",
          pad = "0")

smo_9 = smo_9 %>%
  str_pad(.,
          width = 7,
          side = "right",
          pad = "0")

pne_9 = pne_9 %>%
  str_pad(.,
          width = 7,
          side = "right",
          pad = "0")
