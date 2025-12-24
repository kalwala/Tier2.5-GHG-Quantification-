# Tier-2.5 N₂O Emission Quantification (Cotton) + Spatial Mapping  
**Region:** Maharashtra, India  
**Approach:** Tier-2 / Tier-2.5 style emission factors + activity data integration (fertilizer, organic inputs, crop residues, soil, livestock)  
**Outputs:** Field-level N₂O emissions (direct + indirect) and spatial distribution maps

---

## Overview
This repository contains an R workflow to quantify **N₂O emissions (per farm/plot and per hectare)** using a **Tier-2.5 style approach**, integrating:
- Synthetic N input (FSN)
- Organic N input (FON: manure + compost)
- Crop residue N (FCR)
- Soil organic matter N (FSOM)
- Livestock manure N (FPRP)
- Indirect emissions via volatilization and leaching pathways  
It also generates **spatial maps** and **distribution plots** for emissions in kg N₂O/ha.

---

## Key Outputs
The pipeline generates:
- `Final_N2O_Emissions.csv`  
  - Total direct emissions (kg N and kg N₂O)  
  - Total indirect emissions (kg N and kg N₂O)  
  - Total emissions (kg N and kg N₂O)  
  - Emissions per hectare (`Total_N2O_in_kg_per_ha`)
- `N2O_Spatial_Map.png` (spatial distribution map)
- `N2O_density_Map.png` (histogram + density curve)
- `N2O_box_plot.png` (overall boxplot)
- District-wise boxplot (shown in R plotting section)

---

## Input Data (Required Files)
Place these files in your working directory:
1. **Survey/field dataset (Stata):** `Jul14_FCID.dta`  
2. **Bulk density estimates (Excel):** `Jul14_FCID_with_estimated_BD.xlsx`

### Required columns used from the survey `.dta`
- `hhid`, `id`, `lon`, `lat`
- `e_bp_land_cotton` (cotton area)
- `e_bp_cotton_n_all_kg` (total synthetic N applied, kg)
- `e_bp_manure`, `e_bp_compost`
- `e_num_animals`
- `e_bp_cotton_harvest_kg` (harvest / yield)
- `e_bp_retain_crop_res` (fraction of residue retained)
- `b_soil_oc` (SOC)
- `b_district` (district)

### Required column used from Excel
- `id`
- `estimated_bd`

---

## Methods Summary (What the script does)
### 1) Data preparation
- Reads `.dta` (survey inputs) and `.xlsx` (estimated bulk density)
- Merges both datasets using `id`
- Renames variables into analysis-friendly names:
  - `FSN`, `Area`, `yield`, `SOC`, `BD`, `Dist`, `Manure`, `Compost`, `res`

### 2) Organic N (FON)
- Computes organic N from manure and compost using fixed N contents:
  - Compost N fraction: 0.8%
  - Manure N fraction: 0.7%

### 3) Crop residue N (FCR)
- Computes stalk yield using Harvest Index (HI)
- Uses RS ratio and N fractions for above-/below-ground residues
- Applies retention fraction `res`

### 4) Soil organic matter N (FSOM)
- Estimates mineralization-related N and converts to N₂O using EFSOM

### 5) Livestock pathway (FPRP)
- Estimates manure N contribution using animal numbers and constants (GD, Nex, Nc, NS)
- Converts to N₂O using EF3PRP

### 6) Direct emissions
- Applies district-specific emission factors (EF1_1, EF1_2) and fixed factor for residue (EF1_3)
- Sums all direct pathways and converts kg N → kg N₂O

### 7) Indirect emissions
- Calculates:
  - Atmospheric deposition pathway (`N2O_ATD_N`)
  - Leaching/runoff pathway (`N2O_L_N`)
- Adds to direct to get total emissions

### 8) Per hectare emissions
- Converts totals to:
  - `Total_N2O_in_N_kg_per_ha`
  - `Total_N2O_in_kg_per_ha`

### 9) Spatial and distribution plots
- Filters missing coordinates
- Removes extreme outliers (`N2O_kg_per_ha > 10`)
- Generates:
  - Point-based spatial map (sf + ggplot2)
  - Density/histogram plot
  - Boxplots (overall + district-wise)

---

## How to Run
### 1) Install packages (first time only)
```r
install.packages(c("haven","dplyr","readxl","readr","ggplot2","sf","viridis"))
