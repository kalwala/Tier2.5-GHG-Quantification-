
library(haven)
library(dplyr)

raw_data <- read_dta("Jul14_FCID.dta")
BD_data <- read_excel("Jul14_FCID_with_estimated_BD.xlsx")

colnames(BD_data)

head(raw_data)
colnames(raw_data)

q_data <- raw_data %>%
  select(
    hhid, id, lon, lat,
    e_bp_land_cotton,
    e_bp_cotton_n_all_kg,     
    e_bp_manure,        
    e_bp_compost,      
    e_num_animals,           
    e_bp_cotton_harvest_kg,  
    e_bp_retain_crop_res,     
    b_soil_oc, b_district)

q_data1 <- left_join(q_data, BD_data %>% select(id, estimated_bd), by = "id")
colnames(q_data1)

q_data2 <- q_data1 %>%
  rename(
    FSN        = e_bp_cotton_n_all_kg,
    Area       = e_bp_land_cotton,
    yield      = e_bp_cotton_harvest_kg,
    N_C        = e_num_animals,
    SOC        = b_soil_oc,
    Dist       = b_district,
    BD         = estimated_bd,
    Manure     = e_bp_manure,
    Compost    = e_bp_compost,
    res        = e_bp_retain_crop_res)

q_data3 <- q_data2 %>%
  mutate(
    FON = (Compost * (0.8 / 100)) + (Manure * (0.7 / 100)))

q_data4 <- q_data3 %>%
  mutate(
    HI = 0.5,                          
    RSratio = 0.23,                  
    FRAC_NAGCR = 0.008,              
    FRAC_NBGCR = 0.009,             
    Stalk_yield = ((yield / HI) - yield),                                  
    FAGCR = Stalk_yield * FRAC_NAGCR,                                    
    FBGCR = (yield + Stalk_yield) * RSratio * FRAC_NBGCR,              
    FCR = FAGCR + FBGCR,                                                
    FCR1 = FCR * res)

q_data5 <- q_data4 %>%
  mutate(
    crop_duration = 140,            
    coef_A = 20,
    coef_B = 1000,
    RM_CN = 0.0000085,
    EFSOM = 0.0024,
    FSOM = SOC * BD * crop_duration * coef_A * coef_B * RM_CN,    
    FSOM_in_Kg_N2O = FSOM * EFSOM)

q_data6 <- q_data5 %>%
  mutate(
    GD = 0.5, 
    Nex_C = 8500,         
    Nc = 0.01,                 
    NS_C = 0.02,             
    EF3PRP = 0.004,   
    FPRP = N_C * GD * Nex_C * Nc * NS_C,       
    FPRP_in_Kg_N2O = FPRP * EF3PRP)

q_data7 <- q_data6 %>%
  mutate(
    EF1_1 = case_when(
      Dist == "Nagpur" ~ 1.09,
      Dist == "Wardha" ~ 1.19,
      Dist == "Amravati" ~ 1.91,
      TRUE ~ NA_real_),
  EF1_2 = case_when(
      Dist == "Nagpur" ~ 1.73882,
      Dist == "Wardha" ~ 1.88944,
      Dist == "Amravati" ~ 1.715,
      TRUE ~ NA_real_),
  EF1_3 = 1.47)

q_data8 <- q_data7 %>%
  mutate(
    FSN_kg_N2O = (FSN * EF1_1) / 100,
    FON_kg_N2O = (FON * EF1_2) / 100,
    FCR_kg_N2O = (FCR1 * EF1_3) / 100,
    Total_direct_emissions_in_Kg_N = FSN_kg_N2O + FON_kg_N2O + FCR_kg_N2O + FSOM_in_Kg_N2O + FPRP_in_Kg_N2O,
    Total_direct_emissions_in_N2O = Total_direct_emissions_in_Kg_N * (44 / 28))

########## Indirect emissions

q_data9 <- q_data8 %>%
  mutate(
    # Constants
    FRAC_GASFc = 0.15,
    FRAC_GASMc = 0.15,
    EF_4c = 0.005,
    FRAC_leachC = 0.1,
    EF_5c = 0.005,
    N2O_ATD_N = ((FSN * (FRAC_GASFc / 100)) + ((FON + FPRP) * (FRAC_GASMc / 100))) * EF_4c,
    N2O_L_N = ((FSN + FON + FCR1 + FSOM + FPRP) * (FRAC_leachC / 100) * (EF_5c / 100)),
    
    Total_indirect_emissions_in_Kg_N = N2O_ATD_N + N2O_L_N,
    Total_indirect_emissions_in_N2O = Total_indirect_emissions_in_Kg_N * (44 / 28))

q_data10 <- q_data9 %>%
  mutate(
    Total_emissions_in_Kg_N = Total_direct_emissions_in_Kg_N + Total_indirect_emissions_in_Kg_N,
    Total_emissions_in_N2O = Total_emissions_in_Kg_N * (44 / 28), 
    Total_N2O_in_N_kg_per_ha = Total_emissions_in_Kg_N / Area,
    Total_N2O_in_kg_per_ha = Total_emissions_in_N2O / Area)

write.csv(q_data10, "Final_N2O_Emissions.csv", row.names = FALSE)



########################### Data check

# Total original data
n_total <- nrow(data)

# Missing lon/lat
n_missing_coords <- data %>% filter(is.na(lon) | is.na(lat)) %>% nrow()

# Number of outliers (N2O > 10)
n_outliers <- data %>%
  filter(!is.na(lon) & !is.na(lat)) %>%
  filter(N2O_kg_per_ha > 10) %>%
  nrow()

# Records with complete data: all required fields must be present
required_fields <- c("lon", "lat", "FSN", "Area", "N2O_kg_per_ha")

data_valid <- data %>%
  filter(if_all(all_of(required_fields), ~ !is.na(.))) 

# Now filter valid and remove outliers
data_clean <- data_valid %>%
  filter(N2O_kg_per_ha <= 10)

#####################################

########## Spatial code

library(ggplot2)
library(sf)
library(dplyr)
library(readr)

data <- read_csv("Final_N2O_Emissions.csv")

# Step 2: Create derived columns
data <- data %>%
  mutate(
    N2O_kg_per_ha = Total_N2O_in_kg_per_ha,
    N_kg_per_ha = FSN / Area
  )

data_no_na <- data %>%
  filter(!is.na(lon) & !is.na(lat))

outliers <- data_no_na %>%
  filter(N2O_kg_per_ha > 10)

data_clean <- data_no_na %>%
  filter(N2O_kg_per_ha <= 10)





points_sf <- st_as_sf(data_clean, coords = c("lon", "lat"), crs = 4326)

ggplot() +
  geom_sf(data = points_sf, aes(color = N2O_kg_per_ha), size = 2) +
  scale_color_viridis_c(option = "plasma", name = "N₂O (kg/ha)") +
  theme_minimal() +
  labs(title = "Spatial Distribution of N2O Emissions (kg/ha)",
       x = "Longitude", y = "Latitude")

library(viridis)

A<-ggplot() +
  geom_sf(data = points_sf, aes(fill = N2O_kg_per_ha), 
          size = 2.5, alpha = 0.85, shape = 21, color = "red", stroke = 0.2) +
  scale_fill_viridis_c(option = "plasma", name = expression(N[2]*O~"(kg/ha)")) +
  theme_minimal(base_size = 14) +
  labs(title = " Spatial Distribution of N₂O Emissions (kg/ha)",
       subtitle = "Based on Tier-2 IPCC Methodology",
       x = "Longitude", y = "Latitude") +
  theme(
    panel.grid = element_line(color = "gray85", linetype = "dotted"),
    panel.background = element_rect(fill = "white"),
    plot.title = element_text(face = "bold", size = 16, color = "#4B0092"),
    plot.subtitle = element_text(size = 12, color = "gray40"),
    legend.position = "right",
    legend.title = element_text(size = 12),
    legend.text = element_text(size = 10)
  )

ggsave(plot = A, "N2O_Spatial_Map.png", bg = "white", width = 9, height = 6, units = "in", dpi = 600)

############### Density plot

B<-ggplot(data_clean, aes(x = N2O_kg_per_ha)) +
  # Histogram
  geom_histogram(aes(y = ..count..), binwidth = 0.5, fill = "#0072B2", color = "black", alpha = 0.7) +
  
  # Count labels
  stat_bin(binwidth = 0.5, aes(y = ..count.., label = ..count..),
           geom = "text", vjust = -0.5, color = "black", size = 3.5) +
  
  # Density curve (scaled to count range)
  geom_density(aes(y = ..density.. * nrow(data_clean) * 0.5),  # scale to match histogram
               color = "red", size = 1.2, alpha = 0.7) +
  
  labs(
    title = "Distribution of N2O Emissions (kg/ha)",
    subtitle = "",
    x = expression(N[2]*O~"Emissions (kg/ha)"),
    y = "Count"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", size = 16, color = "#2E4053"),
    plot.subtitle = element_text(size = 12, color = "gray40"),
    panel.grid = element_line(color = "gray85"))


ggsave(plot = B, "N2O_density_Map.png", bg = "white", width = 9, height = 6, units = "in", dpi = 600)


############ Box-plot

C<-ggplot(data_clean, aes(x = "", y = N2O_kg_per_ha)) +
  # Boxplot with narrower width and red outliers
  geom_boxplot(width = 0.35, fill = "#009E73", color = "black", outlier.shape = NA) +
  
  # Add all points (including outliers)
  geom_jitter(aes(color = N2O_kg_per_ha > quantile(N2O_kg_per_ha, 0.75) + 1.5 * IQR(N2O_kg_per_ha) |
                    N2O_kg_per_ha < quantile(N2O_kg_per_ha, 0.25) - 1.5 * IQR(N2O_kg_per_ha)),
              width = 0.12, size = 2, alpha = 0.2) +
  
  scale_color_manual(
    values = c("FALSE" = "blue", "TRUE" = "red"),
    labels = c("FALSE" = "Normal", "TRUE" = "Outlier"),
    name = "Point Type"
  ) +
  
  labs(
    title = "Box Plot of N2O Emissions (kg/ha)",
    y = expression(N[2]*O~"Emissions (kg/ha)")
  ) +
  
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 16, color = "#2E4053"),
    panel.grid = element_line(color = "gray85"),
    axis.title.x = element_blank(),
    axis.text.x = element_blank(),
    axis.ticks.x = element_blank())
ggsave(plot = C, "N2O_box_plot.png", bg = "white", width = 9, height = 6, units = "in", dpi = 600)


########## Boplot for districts 

data_clean$Dist <- factor(data_clean$Dist)

# Define outlier limits
Q1 <- data_clean %>%
  group_by(Dist) %>%
  summarise(Q1 = quantile(N2O_kg_per_ha, 0.25, na.rm = TRUE),
            Q3 = quantile(N2O_kg_per_ha, 0.75, na.rm = TRUE),
            IQR = IQR(N2O_kg_per_ha, na.rm = TRUE)) %>%
  mutate(lower = Q1 - 1.5 * IQR, upper = Q3 + 1.5 * IQR)

# Join with main data to classify outliers
data_plot <- left_join(data_clean, Q1, by = "Dist") %>%
  mutate(outlier_flag = N2O_kg_per_ha < lower | N2O_kg_per_ha > upper)

# Plot
ggplot(data_plot, aes(x = Dist, y = N2O_kg_per_ha)) +
  geom_boxplot(width = 0.4, fill = "grey", outlier.shape = NA) +
  geom_jitter(
    aes(color = outlier_flag),
    width = 0.15,
    alpha = 0.3,
    size = 1.5
  ) +
  scale_color_manual(
    values = c("TRUE" = "red", "FALSE" = "blue"),
    labels = c("TRUE" = "Outlier", "FALSE" = "Normal"),
    name = "Point Type"
  ) +
  labs(
    title = "District-wise Box Plot of N₂O Emissions (kg/ha)",
    y = expression(N[2]*O~"Emissions (kg/ha)"),
    x = ""
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 12, color = "#2E4053"),
    axis.text.x = element_text(hjust = 0.5, face = "bold", size = 12, colour = "navy""),
    panel.grid = element_line(color = "gray85"))
