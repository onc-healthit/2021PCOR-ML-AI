#ICD9 codes from CCS
#Utility file: Used by the script *dxCodeGrouping.R* to produce the table `dxMap`
#Group codes related to alcohol abuse, drug abuse, pulmonary disorders, 
#and renal failure based on the Clinical classification system (CCS) rules for grouping ICD10 diagnosis codes.
#https://www.hcup-us.ahrq.gov/toolssoftware/ccs/ccs.jsp#download

#pneumonia codes
pne_10 = c(
  'J09X1',
  'J1000',
  'J1001',
  'J1008',
  'J1100',
  'J1108',
  'J168',
  'J17',
  'J180',
  'J181',
  'J188',
  'J189',
  'J851',
  'J95851'
)


#copd codes
pne_10 = union(
  pne_10,
  c(
    'J410',
    'J411',
    'J418',
    'J42',
    'J430',
    'J431',
    'J432',
    'J438',
    'J439',
    'J440',
    'J441',
    'J449',
    'J470',
    'J471',
    'J479'
  )
)


#smoking codes
line1 = "Z87891"
smo_10 = line1
smo_10 = union(
  smo_10,
  c(
    'F17200',
    'F17203',
    'F17208',
    'F17209',
    'F17210',
    'F17213',
    'F17218',
    'F17219',
    'F17220',
    'F17223',
    'F17228',
    'F17229',
    'F17290',
    'F17293',
    'F17298',
    'F17299',
    'O99330',
    'O99331',
    'O99332',
    'O99333',
    'O99334',
    'O99335'
  )
  
)



#symptoms of substance use disorders
drg_10 = c(
  'R450',
  'R451',
  'R452',
  'R453',
  'R454',
  'R455',
  'R456',
  'R457',
  'R4581',
  'R4582',
  'R4583',
  'R4584',
  'R45850',
  'R4586',
  'R4587',
  'R4589',
  'R460',
  'R461',
  'R462',
  'R463',
  'R464',
  'R465',
  'R466',
  'R467',
  'R4681',
  'R4689'
)
#abnormal findings related to substance use
drg_10 = union(drg_10, c('R780',
                         'R781',
                         'R782',
                         'R783',
                         'R784',
                         'R785',
                         'R786'))
#cannabis-related disorders
drg_10 = union(
  drg_10,
  c(
    'F1210',
    'F12120',
    'F12121',
    'F12122',
    'F12129',
    'F1213',
    'F12188',
    'F1219',
    'F1220',
    'F12220',
    'F12221',
    'F12222',
    'F12229',
    'F1223',
    'F12288',
    'F1229',
    'F1290',
    'F12920',
    'F12921',
    'F12922',
    'F12929',
    'F1293',
    'F12988',
    'F1299'
  )
)
#hallucinogen-related disorders
drg_10 = union(
  drg_10,
  c(
    'F1610',
    'F16120',
    'F16121',
    'F16122',
    'F16129',
    'F1614',
    'F16183',
    'F16188',
    'F1619',
    'F1620',
    'F16220',
    'F16221',
    'F16229',
    'F1624',
    'F16283',
    'F16288',
    'F1629',
    'F1690',
    'F16920',
    'F16921',
    'F16929',
    'F1694',
    'F16983',
    'F16988',
    'F1699'
  )
)
#opioid-related disorders
drg_10 = union(
  drg_10,
  c(
    'F1110',
    'F11120',
    'F11121',
    'F11122',
    'F11129',
    'F1113',
    'F1114',
    'F11181',
    'F11182',
    'F11188',
    'F1119',
    'F1120',
    'F11220',
    'F11221',
    'F11222',
    'F11229',
    'F1123',
    'F1124',
    'F11281',
    'F11282',
    'F11288',
    'F1129',
    'F1190',
    'F11920',
    'F11921',
    'F11922',
    'F11929',
    'F1193',
    'F1194',
    'F11981',
    'F11982',
    'F11988',
    'F1199'
  )
)
#alcohol-related disorders
alc_10 = c(
  'F1010',
  'F10120',
  'F10121',
  'F10129',
  'F10130',
  'F10131',
  'F10132',
  'F10139',
  'F1014',
  'F10181',
  'F10182',
  'F10188',
  'F1019',
  'F1020',
  'F10220',
  'F10221',
  'F10229',
  'F10230',
  'F10231',
  'F10232',
  'F10239',
  'F1024',
  'F1026',
  'F1027',
  'F10281',
  'F10282',
  'F10288',
  'F1029',
  'F10920',
  'F10921',
  'F10929',
  'F10930',
  'F10931',
  'F10932',
  'F10939',
  'F1094',
  'F1096',
  'F1097',
  'F10981',
  'F10982',
  'F10988',
  'F1099',
  'G312',
  'G621',
  'O354XX0',
  'O354XX1',
  'O354XX2',
  'O354XX3',
  'O354XX4',
  'O354XX5',
  'O354XX9',
  'O99310',
  'O99311',
  'O99312',
  'O99313',
  'O99314',
  'O99315'
)


#renal-failure codes
line1 = "N170 N171 N172 N178 N179 N19"
kid_10 = line1 %>% strsplit(split = " ") %>% unlist()

alc_10 = alc_10 %>%
  str_pad(.,
          width = 7,
          side = "right",
          pad = "0")
drg_10 = drg_10 %>%
  str_pad(.,
          width = 7,
          side = "right",
          pad = "0")
kid_10 = kid_10 %>%
  str_pad(.,
          width = 7,
          side = "right",
          pad = "0")
smo_10 = smo_10 %>%
  str_pad(.,
          width = 7,
          side = "right",
          pad = "0")
pne_10 = pne_10 %>%
  str_pad(.,
          width = 7,
          side = "right",
          pad = "0")
