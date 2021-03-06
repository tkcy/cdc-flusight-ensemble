## script to generate real-time ensemble entry file
## Nicholas Reich
## created: November 2017
## updated: October 2018

library(FluSight) ## devtools::install_github("jarad/FluSight")
library(dplyr)
library(gridExtra)
library(ggplot2)
library(stringr)
library(lubridate)
theme_set(theme_minimal())

## Takes epiweek number as (first) command line argument
args <- commandArgs(TRUE)
#args <- 42

source("scripts/stack_forecasts.R")

THIS_SEASON <- "2018/2019"
THIS_EW <- as.numeric(args[1])
cat(paste0("Generating ensemble files for week ", THIS_EW))

this_year <- ifelse(
    THIS_EW>=40,
    substr(THIS_SEASON, 0, 4),
    substr(THIS_SEASON, 6, 9))
this_week_name <- paste0("EW", str_pad(THIS_EW, 2, pad = "0"), "-", this_year)

## get list of component models
model_names <- read.csv("model-forecasts/component-models/model-id-map.csv",
    stringsAsFactors = FALSE)

## get weights data.frame for used weights
weight_files <- list.files("weights")

for(j in 1:length(weight_files)){
    stacking_weights <- read.csv(paste0("weights/", weight_files[j]),
        stringsAsFactors=FALSE)
    stacked_name <- sub(pattern = ".csv", replacement = "", weight_files[j])
    dir.create(file.path("model-forecasts", "real-time-ensemble-models", stacked_name),
        showWarnings = FALSE)

    wt_subset <- dplyr::filter(stacking_weights, season==THIS_SEASON) %>%
        dplyr::select(-season)
    weight_var_cols <- colnames(wt_subset)[!(colnames(wt_subset) %in% c("component_model_id", "weight"))]

    ## assemble files to stack
    files_to_stack <- paste0(
        "model-forecasts/real-time-component-models/",
        model_names$model.dir, "/",
        this_week_name, "-", model_names$model.dir, ".csv"
    )
    file_df <- data.frame(
        file = files_to_stack,
        model_id = model_names$model.id,
        stringsAsFactors = FALSE)

    ## check files exist, modify weights if they don't
    if(!all(file.exists(files_to_stack))){
        warning(paste(
            length(files_to_stack) - sum(file.exists(files_to_stack)),
            "component files are missing.")
        )

        ## id which files don't exist
        missing_model_ids <- file_df[!file.exists(file_df$file),"model_id"]

        ## remove those rows from wt_subset
        wt_subset <- dplyr::filter(
            wt_subset,
            !(component_model_id %in% missing_model_ids)
            )

        ## standardize weights
        wt_subset <- wt_subset %>%
            group_by_at(vars(weight_var_cols)) %>%
            mutate(weight = weight/sum(weight)) %>%
            ungroup()

        ## remove corresponding rows from file_df
        file_df <- dplyr::filter(file_df, !(model_id %in% missing_model_ids))
    }

    ## check that weights sum to 1 in proper groups
    tot_target_weights <- wt_subset %>%
        group_by_at(vars(weight_var_cols)) %>%
        summarize(total_weights = sum(weight))
    all_weights_sum_to_1 <- base::all.equal(
        tot_target_weights$total_weights,
        rep(1, nrow(tot_target_weights))
    )
    if(!all_weights_sum_to_1)
        stop(paste("Not all model weights sum to 1 for", weight_file[j]))

    ## create, save ensemble file
    stacked_entry <- stack_forecasts(file_df, wt_subset)
    stacked_file_name <- paste0(
        "model-forecasts/real-time-ensemble-models/",
        stacked_name, "/", this_week_name, "-", stacked_name, ".csv"
    )
    if(file.exists(stacked_file_name))
        warning(paste("Ensemble file already exists. Overwriting", stacked_file_name))

    write.csv(stacked_entry, file=stacked_file_name,
        row.names = FALSE, quote = FALSE)
}

## move/rename submission file
tw_file <- paste0(
  "model-forecasts/real-time-ensemble-models/target-based-weights/",
  this_week_name, "-", "target-based-weights.csv"
)

## We use Eastern time here so that the files generated by travis have correct timestamps
## relative to manually generated files
current_date <- date(with_tz(Sys.time(), tzone = "America/New_York"))
tw_submission_file <- paste0(
  "model-forecasts/submissions/target-based-weights/",
  "EW", str_pad(THIS_EW, 2, pad = "0"), "-", this_year, "-FSNetwork-", current_date, ".csv"
)

file.copy(tw_file, tw_submission_file, overwrite = TRUE)


## visualize the TW submission
d <- read_entry(tw_submission_file)

tw_plots_name <- paste0(
    "model-forecasts/submissions/plots/", this_week_name, ".pdf"
)
pdf(tw_plots_name, width = 12)
for(reg in unique(d$location)){
    p_onset <- plot_onset(d, region = reg) + ylim(0,1) +
        theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust=.5, size=5))
    p_peakpct <- plot_peakper(d, region = reg) + ylim(0,1)
    p_peakwk <- plot_peakweek(d, region = reg) + ylim(0,1) +
        theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust=.5, size=5))
    p_1wk <- plot_weekahead(d, region = reg, wk = 1, ilimax=13, years = 2018:2019, plot_current = TRUE) + 
        ggtitle(paste(reg, ": 1 wk ahead")) + ylim(0,1)
    p_2wk <- plot_weekahead(d, region = reg, wk = 2, ilimax=13, years = 2018:2019, plot_current = TRUE) + ylim(0,1)
    p_3wk <- plot_weekahead(d, region = reg, wk = 3, ilimax=13, years = 2018:2019, plot_current = TRUE) + ylim(0,1)
    p_4wk <- plot_weekahead(d, region = reg, wk = 4, ilimax=13, years = 2018:2019, plot_current = TRUE) + ylim(0,1)
    grid.arrange(p_1wk, p_2wk, p_3wk, p_4wk, p_onset, p_peakpct, p_peakwk, ncol=4)
}
dev.off()

## probability past peak plot
# library(tidyr)
# library(cdcfluview)
# library(fiftystater)
# library(grid)
# library(cowplot)
# d <- read_entry(tw_file)
# 
# #week processing 
# d_peak <- subset(d, target == "Season peak week" & 
#     type == "Bin")
# d_peak$Week <- c(1:33)[as.factor(d_peak$bin_start_incl)]
# d_peak$bin_start_incl <- factor(substr(d_peak$bin_start_incl, 1, 
#     nchar(d_peak$bin_start_incl) - 2),
#     levels=paste(c(40:52, 1:20), sep = ""))
# 
# get_past_weeks <- function(THIS_EW){
#     if (THIS_EW >=40) {
#         past_weeks <- factor(c(40:THIS_EW))  
#     } else {
#         past_weeks <- factor(c(40:52, 1:THIS_EW),
#         levels=paste(c(40:52, 1:THIS_EW), sep = ""))
#     }
#     return(past_weeks)
# }
# 
# ## calculate prob past peak from current EW (2 wks ahead of THIS_EW)
# past_weeks <- get_past_weeks(THIS_EW + 2)
# 
# ## sum probabilities before current EW
# probs <- d_peak %>% 
#     group_by(location) %>% 
#     summarise(prob_past_peak = sum(ifelse(bin_start_incl %in% past_weeks, 
#         value, 0)))
# ## region processing for map plot
# data(hhs_regions)
# 
# probs_region <- probs[1:10,1:2]
# probs_region$region_number <- gsub("[^0-9]", "", probs_region$location)
# 
# not_50 <- c(9, 10, 12, 50:55)
# hhs_regions <- hhs_regions[-(not_50),]
# hhs_regions <- merge(hhs_regions, probs_region, by = "region_number")
# hhs_regions$state <- tolower(hhs_regions$state_or_territory)
# 
# ## map plot
# p1 <- ggplot(hhs_regions, aes(map_id = state)) + 
#     geom_map(aes(fill = prob_past_peak), map = fifty_states) +
#     scale_fill_gradient2(low="blue", mid="white", high="red", midpoint=.5) + 
#     expand_limits(x = fifty_states$long, y = fifty_states$lat) +
#     coord_map() +
#     annotate("text", x = -118, y =  45, label = "HHS Region 10") +
#     annotate("text", x = -119.48333, y =  40, label = "HHS Region 9") +
#     annotate("text", x = -105.48333, y =  44, label = "HHS Region 8") +
#     annotate("text", x = -92.1, y =  45, label = "HHS Region 5") +
#     annotate("text", x = -97, y =  40, label = "HHS Region 7") +
#     annotate("text", x = -101, y =  35, label = "HHS Region 6 ") +
#     annotate("text", x = -85, y =  35, label = "HHS Region 4") +
#     annotate("text", x = -78.4, y =  38.5, label = "HHS Region 3") +
#     annotate("text", x = -76, y =  42.55, label = "HHS Region 2") +
#     annotate("text", x = -69.5, y =  44.75, label = "HHS Region 1 ") +
#     scale_x_continuous(breaks = NULL) + 
#     scale_y_continuous(breaks = NULL) +
#     labs(x = NULL, y = NULL) +
#     theme(legend.position = "none", 
#         panel.background = element_blank())
# 
# ## diverging lollipop chart
# p2 <- ggplot(probs, aes(y=reorder(`location`, prob_past_peak), 
#     x=prob_past_peak, label=round(prob_past_peak, 2))) +
#     geom_vline(xintercept = 0.5, color = "grey") + 
#     scale_color_gradient2(low="blue", mid="white", high="red", midpoint=.5) +
#     geom_segment(aes(x = 0.5, 
#         xend = round(prob_past_peak, 2), 
#         yend = reorder(`location`, prob_past_peak),
#         color = prob_past_peak)) +
#     geom_point(stat='identity', size=8, aes(color=prob_past_peak)) +
#     geom_text(color="black", size=3) +
#     labs(y=NULL, x = "Probability Past Peak") +
#     scale_x_continuous(expand=c(0,.01), limits=c(0,1))+
#     theme(legend.position = "none")
# 
# date_str <- paste("6-", THIS_EW + 2,"-",this_year, sep="")
# date <- as.Date(date_str,'%u-%W-%Y')
# title_str = paste("Forecasted Probability of U.S. Flu Season Peaking by ", 
#     month(date), "/",
#     day(date),"/",
#     substr(year(date), 3,4), sep="")
# title <- ggdraw() + draw_label(title_str, fontface='bold')
# p <- plot_grid(p1, p2, ncol = 2, rel_widths=c(12/20, 8/20))
# 
# prob_plot_name <- paste0(
#     "plots/prob_past_peak_",this_week_name, ".png"
# )
# 
# png(prob_plot_name, width = 1208, height=471)
# plot_grid(title, p, ncol = 1, rel_heights=c(0.1, 1))
# dev.off()