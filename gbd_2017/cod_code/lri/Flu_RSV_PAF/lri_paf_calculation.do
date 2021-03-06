// Purpose: Calculate LRI PAFs including DisMod output, static odds ratios, and CFR correction
clear all
set more off
set maxvar 32000
** Set directories
	if c(os) == "Windows" {
		global j "J:"
		
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set mem 2g

		set odbcmgr unixodbc
	}
qui do "FILEPATH/get_draws.ado"	
use "FILEPATH/dismod_eti_covariates.dta", clear
	tempfile cvs
	save `cvs'
	
// influenza and RSV me_ids //
local id 1259 1269
local id 1259
local sex 1 2
local year 1990 1995 2000 2005 2010 2017
// Loop influenza and RSV by location, year, and sex 
// Creates a pair of PAF csvs for each modelable_entity_id 
// One for YLLs and one for YLDs that will be inputs for the DALYnator //
foreach me_id in `id' {
// Get DisMod proportion draws //
	get_draws, gbd_id_type(modelable_entity_id) source(epi) gbd_id(`me_id') location_id(`1') year_id(`year') sex_id(`sex') clear
		keep if age_group_id != 22
		drop if age_group_id == 21 | age_group_id == 27 | age_group_id == 164 | age_group_id == 33
		gen dummy = 1
		tempfile draws
		save `draws'
	di "Pulled proportion draws"	
// DisMod models have a covariate for 'severity' 
// the assumption is that the proportion of LRI cases that are positive for viral etiologies
// is lower among severe than non-severe LRI cases //	
	local best = model_version_id[1]
	
	use `cvs', clear
	keep if modelable_entity_id == `me_id'

	keep scalar_* model_version_id
	gen dummy = 1
	merge m:m dummy using `draws', force
	drop _m dummy
	save `draws', replace
	
	di "Saved scalar draws"
	
// Previously created file with 1000 draws of the odds ratio of LRI given pathogen presence //			
	use "FILEPATH/odds_draws.dta", clear
		keep if modelable_entity_id==`me_id'

	merge 1:m age_group_id using `draws', nogen
		gen rei_id = 190
		replace rei_id = 187 if `me_id' == 1259
		gen rei_name = "eti_lri_flu"
		replace rei_name = "eti_lri_rsv" if `me_id' == 1269
		local rei = rei_name[1]
	
	preserve
// Generate YLD PAF is proportion * (1-1/odds ratio) //
		qui forval i = 0/999 {
			gen paf_`i' = draw_`i' * (1-1/rr_`i')
			replace paf_`i' = 1 if paf_`i' > 1
	/// No etiology in neo-nates, consistent with GBD 2013/2015/2017 ///
			replace paf_`i' = 0 if age_group_id<=3
		}
		drop rr_*
		drop draw_*
		drop scalar_*
		keep location_id year_id age_group_id sex_id rei_id rei_name cause_id paf_*
		sort year_id age_group_id sex_id
		
		export delimited "FILEPATH/paf_yld_`1'.csv", replace
	di "Saved yld draws"
	restore

// Generate YLL PAF is proportion * severity_scalar * cfr_scalar * (1-1/odds ratio) //
// This is a previously created file with 1000 draws of the ratio of case fatality among viral to bacterial
// causes of LRI by age //
		merge m:1 age_group_id using "FILEPATH/cfr_scalar_draws_full.dta", nogen
		
		qui forval i = 0/999 {
			gen paf_`i' = draw_`i' * (1-1/rr_`i') * scalarCFR_`i' * scalar_`i'
			replace paf_`i' = 1 if paf_`i' > 1
	/// No etiology in neo-nates, consistent with GBD 2013/2015/2017 ///
			replace paf_`i' = 0 if age_group_id<=3
		}

		drop rr_*
		drop draw_*
		drop scalarCFR_*
		drop scalar_*
		keep location_id year_id age_group_id sex_id rei_id rei_name cause_id paf_*
		sort year_id age_group_id sex_id
		export delimited "FILEPATH/paf_yll_`1'.csv", replace
}


