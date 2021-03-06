library(tidyverse) #load packages
library(ggthemes)
library(huxtable)
library(readxl)
library(stringr)
library(readr)

HUD_data <- read.csv(file = "./Documents/PUAD-688/HUD_neighborhood_data.csv") 
county_info_with_populations <- read.csv(file = "./Documents/PUAD-688/RuralAtlasData23People.csv") 
county_info2 <- read.csv(file = "./Documents/PUAD-688/RuralAtlasData23.csv") 
NFIP_Reinsurance_Placement2020 <- read.csv(file = "./Documents/PUAD-688/NFIP_2021_Exposure_by_DTW(2021_NFIP_Reinsurance_Placement_Information).csv") 
  
#Looking at everything
str(HUD_data) #a lot are chr and int 
glimpse(HUD_data)

#New data
HUD_narrowed <- HUD_data %>% select(property_id, address_line1_text, city_name_text, state_code, county_code, county_name_text)

#Checking all the occurences of county names: many of them, some with both upper and lower case writing 
table(HUD_narrowed$county_name_text)

#Making a list of HUD counties 
HUD_counties <- HUD_data %>% select(county_code, county_name_text, state_code)
HUD_county_names <- HUD_data %>% select(county_name_text, state_code)

#Drop if missing
HUD_county_names<- HUD_county_names %>% drop_na() #this doesn't seem to work 
sum(is.na (HUD_county_names)) #It says 0...but clearly some aren't there
#So now, adapt to this problem 
HUD_county_names$county_name_text[HUD_county_names$county_name_text==""] <- 9999 #make NAs equal to 9999
HUD_county_names <- HUD_county_names %>%
  filter(county_name_text != 9999) #drop 9999s

#Add a column to preserve punctuation 
county_info2$Punctuated_county <- county_info2$County

#Change capitalization 
HUD_county_names$county_name_text <- str_to_title(HUD_county_names$county_name_text) #removes all the weird punctuation and standardizes
county_info2$County <- str_to_title(county_info2$County) #makes it match the above

#Check for duplicates 
length(unique(HUD_county_names$county_name_text)) == nrow(HUD_county_names) #FALSE = there are duplicates 

#How many duplicates?
n_occur <- data.frame(table(HUD_county_names$county_name_text)) #so many duplicates...

#Remove duplicates
HUD_county_names$County_and_State <- paste(HUD_county_names$county_name_text, HUD_county_names$state_code, sep="_") #combine columns into new one, County_and_State
HUD_county_names <- HUD_county_names %>% distinct(County_and_State) 

#Separate column to fix 
HUD_county_names <- HUD_county_names %>% separate(County_and_State, c('County', 'State'), "_", convert = TRUE) 
#US Virgin Islands: [2418, 2419, 2420, 2422, 2423]

#Check
str(HUD_county_names)
str(county_info2)

#Make other column in other dataset into integer...probably don't need to do this 
county_info2$PCTPOVALL <- as.integer(county_info2$PCTPOVALL)

#Remove white space trailing words
HUD_county_names$County <- trimws(HUD_county_names$County)
county_info2$County <- trimws(county_info2$County)

#OR delete all white space, but this is messy 
#HUD_county_names$County <- str_replace_all(HUD_county_names$County," ","")
#county_info2$County <- str_replace_all(county_info2$County," ","") 

#Create column with combined names actually...I need this I think
HUD_county_names$County_and_State <- paste(HUD_county_names$County, HUD_county_names$State, sep="_") #squish back together 
county_info2$County_and_State <- paste(county_info2$County, county_info2$State, sep="_") #squish back together 

#Joining 
#joined_county_data <- left_join(HUD_county_names, county_info2, by='County_and_State') #one way to join, but less neat
joined_county_data <- left_join(HUD_county_names, county_info2, by=c('County' = 'County', 'State' = 'State')) #results in 2773 observations

#USEFUL: PCTPOVALL = Total poverty in 2019

#Now fixing up NFIP data for combination by removing one word from phrases
NFIP_data <- NFIP_Reinsurance_Placement2020 %>%
  mutate(County = str_remove_all(County, "COUNTY")) #removing all of COUNTY from county names 

#check out data 
str(NFIP_data)

#Remove commas from numbers and make into integer
NFIP_data$RiskCount <- as.integer((gsub(",", "", NFIP_data$RiskCount)))

#Making the name not be capitalized 
NFIP_data$County <- str_to_title(NFIP_data$County)

#Remove white space 
NFIP_data$County <- trimws(NFIP_data$County)
NFIP_data$State <- trimws(NFIP_data$State)

#Remove duplicates
NFIP_data$County_and_State <- paste(NFIP_data$County, NFIP_data$State, sep="_") #combine columns into new one, County_and_State

#Create column of added up counts within counties to divide by risk numbers
NFIP_data <- NFIP_data%>%
  add_count(County_and_State) #n is the count

#Create column of added up risk counts 
NFIP_data <- NFIP_data%>%
  group_by(County_and_State) %>% 
  mutate(Summed_Risk = sum(RiskCount))

#Get rid of FIPS
NFIP_data <- NFIP_data %>% select(-FIPS)

#Since we don't need everything lets remove duplicates 
NFIP_data$County_and_State <- paste(NFIP_data$County, NFIP_data$State, sep="_")

#Fix names real quick in the joined data set to set up merging 
joined_county_data <- joined_county_data %>% mutate(County_and_State = County_and_State.y)
joined_county_data <- joined_county_data %>% select(-County_and_State.x, -County_and_State.y)

#Get rid of data I don't want right now in NFIP stuff 
NFIP_data <- NFIP_data %>% select(-DTW_band, -RiskCount, -TIV, -Limit, -RollUp_Level, -County, -State)
NFIP_data <- NFIP_data %>%distinct()

#Join NFIP flood reinsurance info to joined dataset
joined_county_data <- left_join(joined_county_data , NFIP_data, by= c('County_and_State' = 'County_and_State'))

#The risk categories are for flood reinsurance 

#New column for risk
joined_county_data <- joined_county_data %>% 
  mutate(Risk_by_Instances_in_County = Summed_Risk/n)

#Look at very poor counties 
poor_counties <- joined_county_data %>%
  filter(PCTPOVALL >= 20) 

#Save data frames as .csv
write_csv(poor_counties, "./Documents/PUAD-688/Poor_Counties.csv")
write_csv(joined_county_data, "./Documents/PUAD-688/Some_Joined_Data.csv")















