# rename "s/bgz/gz/" *.bgz # one-liner to make .bgz files readable for data.table::fread

setwd("~/Documents/Bioinf/BRB5/")
library(dplyr)
library(readxl)
library(stringr)
library(tidyr) 
library(data.table)
library(ggplot2)
library(plotly)
library(RColorBrewer)
library(qqman)
library(GenABEL) 
library(CMplot)
library(viridis)
library(pbapply)  
library(phenoscanner)
library(eulerr)

# I had a problem with an installation of "GenABel" package (R version 3.6.1 (2019-07-05))
# So this is the way to fix it
# install.packages("devtools")
# devtools::install_url("https://cran.r-project.org/src/contrib/Archive/GenABEL.data/GenABEL.data_1.0.0.tar.gz")
# devtools::install_url("https://cran.r-project.org/src/contrib/Archive/GenABEL/GenABEL_1.8-0.tar.gz")


uk_biobank <- read_excel("UKBB GWAS Imputed v3 - File Manifest Release 20180731.xlsx",
                         sheet = 2,na = "N/A",col_names = T)
# removing all stuff which is not from imputed.v3
uk_biobank_v3 <- subset(uk_biobank,grepl(uk_biobank$File,pattern="imputed.v3") & uk_biobank$Sex == "female") 

# I digged in uk biobank and found phenotypes.female.tsv
# there are some phenotypes which could be grepped (patterns related to pregnancy problems)
phenotype_fem <- read.delim("phenotypes.female.tsv")

# downloading datasets with wget_data.sh script 
preg_phen <- read.table("data/my_data.txt",header = F)
preg_phen$`Phenotype Code` <- gsub(preg_phen$V9,pattern = "\\..*",replacement="")
colnames(preg_phen)[9] <- "file"
preg_phen <- plyr::join(preg_phen[,-c(1:8)], uk_biobank_v3[,c(1,2,6)],type="inner")

#rm(uk_biobank,uk_biobank_v3,phenotype_fem)



"For each dataset it calculates:
lambdaGC, number of all snp, high confident snp and snp with pval < 1e-06,1e-07,1e-08
but it put them to one column, so later we'll separate it to multiple columns"

preg_phen$result <- pbsapply(preg_phen$file, function(x){
  
  data <- fread(paste("data/",x, sep=""))
 
  data %>% drop_na() %>% count() -> raw_snp1
  
  data[low_confidence_variant==FALSE] %>% drop_na() -> data
  data %>% count() -> highconf_snp
  
  data %>%  
    dplyr::select(pval) %>%
    summarise(lambdaGC = estlambda(data = pval,plot=F,method = "median")[1]) -> lambdaGC
    as.vector(unlist(lambdaGC)) %>% round(.,digits = 3) -> lambdaGC

  data[pval < 1e-08] %>% count() -> neglog10_P8
  data[pval < 1e-07] %>% count() -> neglog10_P7
  data[pval < 1e-06] %>% count() -> neglog10_P6
  
  total <- paste(raw_snp1,highconf_snp,lambdaGC,neglog10_P6,neglog10_P7,neglog10_P8, sep = ";")
  return(total)
})

# It creates several columns to put there the corresponding information from 'result' column
# and deletes result column in the end
preg_phen$raw_snp <- NA
preg_phen$highconf_snp <- NA
preg_phen$lambdaGC <- NA
preg_phen$log10_P8 <- NA
preg_phen$log10_P7 <- NA
preg_phen$log10_P6 <- NA

preg_phen[,c(6:ncol(preg_phen))] <- data.frame(str_split_fixed(preg_phen$result,pattern = ';',n=Inf))
preg_phen %>% dplyr::select(-result) -> preg_phen
colnames(preg_phen) <- gsub(colnames(preg_phen),pattern = " ",replacement = "_")
# this dataframe contains the data (phenotypes)
# I used for counting SNP with different pval thresholds (-log(p) = [6,7,8]), 
# lambdaGC, raw and high confident SNP numbers
#fwrite(preg_phen,"preg_phen_snp_lGC.tsv",sep = "\t") 

#
preg_phen <- read.table("~/Documents/Bioinf/BRB5_GWAS_PREGNANCY/publication/preg_phen_snp_lGC.tsv",header = T,sep = "\t")
# add n_controls and n_cases and heritability to the table
#preg_phen <- plyr::join(preg_phen,phenotype_fem[,c("phenotype","n_cases","n_controls")] %>% dplyr::rename("Phenotype_Code"=phenotype))
#her <- fread("~/Downloads/ukb31063_h2_topline.02Oct2019.tsv.gz") # heritability dataset UKB
#preg_phen <- plyr::join(preg_phen,her[,c("phenotype","h2_observed")] %>% dplyr::rename("Phenotype_Code"=phenotype))
#preg_phen$h2_observed <- round(preg_phen$h2_observed,4)
#rm(her,phenotype_fem,uk_biobank,uk_biobank_v3)
#write.table(preg_phen,"~/Documents/Bioinf/BRB5_GWAS_PREGNANCY/publication/preg_phen_snp_lGC.tsv",sep = "\t",row.names = F)

# Visualization of preg_phen (pval < 1e-07)
plot1 <- ggplot(preg_phen, aes(Phenotype_Code,lambdaGC))+
  geom_point(aes(size=as.numeric(preg_phen$log10_P7),description = Phenotype_Description, snp = log10_P7),col=brewer.pal(7,"Dark2")[1],alpha=0.9)+
  ylab("Genomic inflation factor")+
  xlab("Phenotype code")+
  labs(size="Number of significant \nSNP (1-e07)")+
  geom_hline(yintercept = 1)+ylim(limits = c(0.9,1.2))+
  theme_bw()+
  theme(axis.text.x = element_text(hjust = 1,angle = 45,size = 10,face = "bold"))+
  scale_size_continuous(range = c(1.5,8))+ylim(NA,1.05)
plot1
# ggplotly for more convinient analysis (to see Phenotype_Code, Phenotype_Description and number of snp with the correspoding threshold)
ggplotly(plot1,tooltip = c("Phenotype_Code","description","snp"))
  
# Visualization of preg_phen (pval < 1e-08)
plot2 <- ggplot(preg_phen, aes(Phenotype_Code,lambdaGC))+
  geom_point(aes(size=as.numeric(preg_phen$log10_P8),description = Phenotype_Description, snp = log10_P8),col=brewer.pal(7,"Dark2")[3],alpha=0.9)+
  ylab("Genomic inflation factor")+
  xlab("Phenotype code")+
  labs(size="Number of significant \nSNP (1-e08)")+
  geom_hline(yintercept = 1)+ylim(limits = c(0.9,1.2))+
  theme_bw()+
  theme(axis.text.x = element_text(hjust = 1,angle = 45,size = 10,face = "bold"))+
  scale_size_continuous(range = c(1.5,8))+ylim(NA,1.05)
plot2
ggplotly(plot2,tooltip = c("Phenotype Code","description","snp"))

# we see, that only 4 datasets have a signal (number of SNP)
# now we're going to analyse them more properly (QQ and Manhattan plots)

# Function for edition datasets for Manhattan and QQ plots
gwas_edit <- function(data){
  data[low_confidence_variant==F][,c(1,12)] %>% drop_na()-> data
  colnames(data)[1] <- "SNP"
  data$Chromosome <- NA
  data$Position <- NA
  data[,c(3,4)] <- as.data.frame(str_split_fixed(data$SNP,":",Inf)[,c(1,2)])
  data <- data[,c(1,3,4,2)]
  data$Position <- sapply(data$Position, as.numeric)
  return(data)
}
# Function for manhattan plot 
# WARNING! It creates Manhattan plot from pval > 0.01 to save time
manhattan_plot <- function(data,pval_threshold,outfile){
  CMplot((data %>% filter(pval < pval_threshold)),
         plot.type = "m",band = 0,LOG10 = TRUE,
         threshold = c(1e-6,1e-7,1e-8),threshold.col = c("blue","green","red"),
         amplify = F,ylim = c(2,9),cex = 0.8,
         file="jpg",memo="",dpi=300,file.output=outfile,verbose=TRUE,width=7,height=6)
}
# Function for QQ plot
qq_plot <- function(data,outfile){
  CMplot(data,plot.type="q",conf.int=TRUE,box=FALSE,file="jpg",memo="",dpi=300,
         ,file.output=outfile,verbose=TRUE,width=5,height=5)
}



# Processing O46 dataset (creating all plots and subsetting for pval < 1e-05)
O46 <- fread("data/O46.gwas.imputed_v3.female.tsv.gz")
O46_p <- gwas_edit(O46) # dataframe for plotting (Manhattan or QQ)
subset(O46_p, O46_p$pval <= 1e-5) -> snp_O46
manhattan_plot(O46_p,0.01,T)
colnames(O46_p)[4] <- "O46 phenotype"
qq_plot(O46_p,outfile = T)
rm(O46,O46_p)

# Processing O26 dataset (creating all plots and subsetting for pval < 1e-05)
O26 <- fread("data/O26.gwas.imputed_v3.female.tsv.gz")
O26_p <- gwas_edit(O26) # dataframe for plotting (Manhattan or QQ)
subset(O26_p, O26_p$pval <= 1e-5) -> snp_O26
manhattan_plot(O26_p,0.01,T)
colnames(O26_p)[4] <- "O26 phenotype"
qq_plot(O26_p,outfile = T)
rm(O26,O26_p)

# Processing O69 dataset (creating all plots and subsetting for pval < 1e-05)
O69 <- fread("data/O69.gwas.imputed_v3.female.tsv.gz")
O69_p <- gwas_edit(O69) 
subset(O69_p, O69_p$pval <= 1e-5) -> snp_O69
manhattan_plot(O69_p,0.01,T)
colnames(O69_p)[4] <- "O69 phenotype"
qq_plot(O69_p,outfile = T)
rm(O69,O69_p)

# Processing I9_HYPTENSPREG dataset (creating all plots and subsetting for pval < 1e-05)
I9_HYPTENSPREG <- fread("data/I9_HYPTENSPREG.gwas.imputed_v3.female.tsv.gz")
I9_HYPTENSPREG_p <- gwas_edit(I9_HYPTENSPREG) 
subset(I9_HYPTENSPREG_p, I9_HYPTENSPREG_p$pval <= 1e-5) -> snp_I9_HYPTENSPREG
manhattan_plot(I9_HYPTENSPREG_p,0.01,T)
colnames(I9_HYPTENSPREG_p)[4] <- "I9_HYPTENSPREG phenotype"
qq_plot(I9_HYPTENSPREG_p,outfile = T)
rm(I9_HYPTENSPREG,I9_HYPTENSPREG_p)

# creating summary table for these 4 datasets
snp_I9_HYPTENSPREG$Dataset <- "I9_HYPTENSPREG" 
snp_O26$Dataset <- "O26" 
snp_O46$Dataset <- "O46" 
snp_O69$Dataset <- "O69" 

ukbiobank_summ <- rbind(snp_I9_HYPTENSPREG,snp_O26,snp_O46,snp_O69)
write.csv(ukbiobank_summ[,c(1,4)],"snp_ukbiobank_summ.csv")





# Processing O26 dataset (creating all plots and subsetting for pval < 1e-05)
O46 <- fread("data/O46.gwas.imputed_v3.female.tsv.gz") 
O46 %>% filter(low_confidence_variant==F & O46$pval <= 1e-05) -> snp_O46
rm(O46)
# Processing O46 dataset (creating all plots and subsetting for pval < 1e-05)
O26 <- fread("data/O26.gwas.imputed_v3.female.tsv.gz") 
O26 %>% filter(low_confidence_variant==F & O26$pval <= 1e-05) -> snp_O26
rm(O26)
# Processing I9_HYPTENSPREG dataset (creating all plots and subsetting for pval < 1e-05)
I9_HYPTENSPREG <- fread("data/I9_HYPTENSPREG.gwas.imputed_v3.female.tsv.gz") 
I9_HYPTENSPREG %>% filter(low_confidence_variant==F & I9_HYPTENSPREG$pval <= 1e-05) -> snp_I9_HYPTENSPREG
rm(I9_HYPTENSPREG)
# Processing O69 dataset (creating all plots and subsetting for pval < 1e-05)
O69 <- fread("data/O69.gwas.imputed_v3.female.tsv.gz")
O69 %>% filter(low_confidence_variant==F & O69$pval <= 1e-05) -> snp_O69
rm(O69)
# creating a column with dataset information for each variant
snp_I9_HYPTENSPREG$Dataset <- "I9_HYPTENSPREG" 
snp_O26$Dataset <- "O26" 
snp_O46$Dataset <- "O46" 
snp_O69$Dataset <- "O69" 

total <- rbind(snp_O46,snp_O26,snp_I9_HYPTENSPREG,snp_O69)
#write.csv(total,"total_ukbiobank_pregn.csv")

# 
total <- read.csv("total_ukbiobank_pregn.csv")
total$variant %>% unique(.) %>% length(.)
variants <- fread("variants.tsv.gz",nrows = 50) # dataset from UKB with metadata for each SNP
plyr::join(total,variants[,c(1:9)],type="inner") -> total
rm(variants)

# saving data for LSEA analysis for all 4 phenotypes from UKB
colnames(total)[c(14,15,18,16,17,12)] <- c("CHR","COORDINATE","RSID","REF","ALT","PVAL")
total[,c("CHR","COORDINATE","RSID","REF","ALT","PVAL","Dataset")] -> ukb_total_lsea

# filtering snp wich don't have rd-id
ukb_total_lsea %>% filter(grepl(.$RSID,pattern='rs')) -> ukb_total_lsea_filt

# exporting tables for 4 UKB phenotypes separately for LSEA
sapply(unique(ukb_total_lsea_filt$Dataset),function(x){
  data <- subset(ukb_total_lsea_filt,ukb_total_lsea_filt$Dataset==x)
  full_name = paste0(noquote(x),".csv",collapse = "")
  write.csv(data[,c("CHR","COORDINATE","REF","ALT","PVAL")],full_name,row.names = F)
})

# exporting tables for all phenotypes separately for LSEA
ukb_total_lsea_filt %>% dplyr::select(-Dataset) %>% write.csv(.,'UKB_total.csv',row.names = F)

###################################################################################################################################
###################################################################################################################################
###################################################################################################################################

# Now we're working with GWAS Catalog 
# gwas_catalog table was manually obtained from GWAS Catalog website
# There we just took all snps which somehow corresponded to pregnancy problems
gwas_catalog <- read_excel("gwas_catalog_rawtable.xlsx",col_names = T)
colnames(gwas_catalog) <- gsub(colnames(gwas_catalog),pattern=" ",replacement = "_")
# Calculation unique and total snp in the whole table
gwas_catalog %>% summarise(total_snp=nrow(.),unique_snp=length(unique(gwas_catalog$Variant_and_risk_allele)))

# this is a file with selected phenotypes from the GWAS Catalog more precisely, removing excess phenotypes
gwas_traits <- read.csv("filt.csv")
gwas_traits$V3 <- paste(gwas_traits$V1,gwas_traits$V2,sep = "_")
gwas_catalog <- subset(gwas_catalog,gwas_catalog$Reported_trait %in% gwas_traits$V1 & gwas_catalog$`Trait(s)` %in% gwas_traits$V2)
gwas_catalog <- subset(gwas_catalog, gwas_catalog$Reported_trait %in% gwas_traits$V1 & gwas_catalog$`Trait(s)` %in% gwas_traits$V2)
gwas_traits <- as.data.frame(table(gwas_catalog$Reported_trait))




# editing of gwas_catalog dataframe 
gwas_catalog$RSID <- as.data.frame(str_split_fixed(gwas_catalog$Variant_and_risk_allele, pattern = "-",n=Inf))[,1]
colnames(gwas_catalog)[2] <- "PVAL"
gwas_catalog$REF <- as.data.frame(str_split_fixed(as.data.frame(str_split_fixed(gwas_catalog$snp_info,pattern=";",n=Inf))[,2],pattern="\\/",Inf))[,1]

# calculation of phenotypes from the GWAS Catalog and the number of SNPs which they account for
ggplot(gwas_traits,aes(reorder(Var1,Freq),Freq))+
  geom_bar(stat = 'identity',fill=brewer.pal(3,'Set1')[2])+
  coord_flip()+
  theme_bw()+ggtitle("GWAS Catalog traits\nrelated to pregnancy problems")+
  ylab("Counts")+xlab("GWAS Catalog phenotypes")+
  theme(axis.text.y = element_text(size=14,colour="black"),
        title = element_text(size=20),axis.text.x=element_text(size=14,colour='black'))


# OUR COLABORATORS ASKED FOR THIS TABLE TO MAKE SOME COMBINATIONS BETWEEN THESE PHENOTYPES
# so I just printed it and sent them 
write.csv(gwas_traits,"GWAS_for_collab.csv")

# correction PVAL column (making it numeric type)
d <- as.data.frame(str_split_fixed(gwas_catalog$PVAL,pattern=" x ",Inf))
d$V1 <- as.numeric(as.character(d$V1))
d <- cbind(d[,1],as.data.frame(str_split_fixed(d$V2,pattern="-",Inf))) 
d[,c(2,3)] <- apply(d[,c(2,3)],c(1,2),as.character) 
d[,c(2,3)] <- apply(d[,c(2,3)],c(1,2),as.numeric) 
d$V1 <- 10**(-d$V2)
gwas_catalog$PVAL <- d$V1
rm(d)

# PHENOSCANNER PACKAGE R SNP annotation 
gwas_catalog$NUC_EXCHANGE <- NA
gwas_catalog$REGION <- NA

gwas_catalog %>%
  dplyr::mutate(NUC_EXCHANGE = pbsapply(.$RSID, function(x){
    res <- phenoscanner(snpquery=x,catalogue = "GWAS")
    if (!(grepl(x,pattern = 'chr')) | all(dim(res$snps)!=0)){
      return(paste0(res$snps[,c(8,9)],collapse="/"))
    } else {
      return("no_data")
    }
  }),
  REGION = pbsapply(.$RSID, function(x){
    res <- phenoscanner(snpquery=x,catalogue = "GWAS")
    if (all(dim(res$snps)!=0)){
      return(paste0(res$snps$consequence,collapse=";"))
    } else {
      return("no_data")
    }
  })) -> gwas_catalog


# counting SNPs with manual annotation manual annotation (25 in total)
gwas_catalog %>% 
  filter(grepl(.$NUC_EXCHANGE,pattern='-')) %>% count()

# counting failed SNP id which contain anything but rsID  (14 in total)
gwas_catalog %>% 
  filter(grepl(.$Variant_and_risk_allele,pattern='rs')==F) %>% count()

# exporting gwas_catalog to be safe
#write.csv(gwas_catalog,"gwas_catalog_annotated.csv")
# then we manually check the SNPs that have crap in REF/ALT columns (chr etc)
# adding REF and ALT from GWAS Catalog

# Now preprocessing of variants from gwas catalog for LSEA
gwas_catalog <- read_excel("gwas_catalog_annotated.xlsx")
gwas_catalog$Location <- gsub(gwas_catalog$Location,pattern="X",replacement = "23") # change name of Х-chromosome to 23
gwas_catalog$REF <- gwas_catalog$REF_man_corr
gwas_catalog$REF <- ifelse(is.na(gwas_catalog$REF),
                                    as.character(as.data.frame(str_split_fixed(gwas_catalog$NUC_EXCHANGE,pattern = "/",Inf))[,1]),
                                    gwas_catalog$REF)
gwas_catalog$ALT <- gwas_catalog$ALT_man_corr
gwas_catalog$ALT <- ifelse(is.na(gwas_catalog$ALT) & gwas_catalog$NUC_EXCHANGE!='no_data' ,
                                    as.character(as.data.frame(str_split_fixed(gwas_catalog$NUC_EXCHANGE,pattern = "/",Inf))[,2]),
                                    gwas_catalog$ALT)
gwas_catalog$ALT <- ifelse(grepl(gwas_catalog$ALT,pattern='/'),
                                    as.character(as.data.frame(str_split_fixed(gwas_catalog$ALT,pattern = "/",Inf))[,2]),
                                    gwas_catalog$ALT)

# Calculation how many valid and non-valid snp do we have by: 
# in REF and ALT column must be something, but not "no_data"
gwas_catalog %>% 
  summarise(non_valid_snp = subset(.,grepl(.$REF,pattern='-') | grepl(.$REF,pattern='no_data') | is.na(.$REF) | 
                                 grepl(.$ALT,pattern='-') | grepl(.$ALT,pattern='no_data') | is.na(.$ALT) |
                                   is.na(.$COORDINATE)) %>% nrow(.), 
            valid_snp = nrow(.)-non_valid_snp,
            total_snp = nrow(.))

# Filtering all valid SNPs to a dataframe 
gwas_catalog %>%
  filter(.,grepl(.$REF,pattern='-')==F & grepl(.$REF,pattern='no_data')==F & is.na(.$REF)==F &
           grepl(.$ALT,pattern='-')==F & grepl(.$ALT,pattern='no_data')==F & is.na(.$ALT)==F & 
           is.na(.$COORDINATE)==F) -> gwas_catalog_filtered

# Creation of CHR column for typical LSEA input
gwas_catalog_filtered$CHR <- as.data.frame(str_split_fixed(gwas_catalog_filtered$Location,pattern = ":",Inf))[,1]

# Export gwas catalog snp for LSEA (total and separated by 25 selected phenotypes)
gwas_catalog_filtered %>% dplyr::select(c(CHR,COORDINATE,RSID,REF,ALT,PVAL)) %>% unique(.) -> gwas_catalog_filtered_lsea
colnames(gwas_catalog_filtered)
gwas_catalog_filtered %>% dplyr::filter(PVAL < 1e-7) %>% 
  dplyr::select(c(CHR,COORDINATE,RSID,REF,ALT,PVAL,Mapped_gene,"Reported_trait")) -> gwas_catalog_filtered_pval
gwas_catalog_filtered %>% dplyr::filter(PVAL < 1e-5) %>% 
  dplyr::select(c(CHR,COORDINATE,RSID,REF,ALT,PVAL,Mapped_gene,"Reported_trait")) -> gwas_catalog_filtered_pval_2
write.table(gwas_catalog_filtered_pval,"~/Documents/Bioinf/BRB5_GWAS_PREGNANCY/publication/gwas_catalog_filtered_pval_07.tsv",row.names = F,sep = "\t")
write.table(gwas_catalog_filtered_pval_2,"~/Documents/Bioinf/BRB5_GWAS_PREGNANCY/publication/gwas_catalog_filtered_pval_05.tsv",row.names = F,sep = "\t")
# Total snp from GWAS Catalog for LSEA
#write.csv(gwas_catalog_filtered_lsea,'~/Documents/Bioinf/BRB5/RESULTS/gwas_catalog_filtered_lsea.csv',row.names = F)

setwd("~/Documents/Bioinf/BRB5/RESULTS/tables_gwascat/")
# separated phenotypes for LSEA
sapply(gwas_traits$Var1,function(x){
  data <- subset(gwas_catalog_filtered,gwas_catalog_filtered$Reported_trait==x)
  # removing 'bad' symbols for file names
  left_name <- gsub(x,pattern='\\(',replacement = "")
  left_name <- gsub(left_name,pattern='\\)',replacement = "")
  left_name <- gsub(left_name,pattern='-',replacement = "_")
  left_name <- gsub(left_name,pattern=' ',replacement = "_")
  left_name <- gsub(left_name,pattern='\\/',replacement = "_")
  full_name = paste0(noquote(left_name),".csv",collapse = "")
  write.csv(data[,c("CHR","COORDINATE","RSID","REF","ALT","PVAL")],full_name,row.names = F)
})

"
After the presentation to Glotov's lab we decided to combine some phenotypes and their variants.
I got this table from them. 
"
glotov_table <- read_excel("Pregnancy.xlsx",col_names = c("N","our_traits","gwas_traits"))
unique(glotov_table$our_traits) 


# These phenotypes were taken under consideration
diab_gest <- subset(gwas_catalog_filtered,gwas_catalog_filtered$Reported_trait %in% glotov_table$gwas_traits[c(1:6)])
preterm_birth <- subset(gwas_catalog_filtered,gwas_catalog_filtered$Reported_trait %in% glotov_table$gwas_traits[c(8:16)])
placental_abrup <- subset(gwas_catalog_filtered,gwas_catalog_filtered$Reported_trait %in% "Placental abruption")
preeclampsia <- subset(gwas_catalog_filtered,gwas_catalog_filtered$Reported_trait %in% "Preeclampsia")
midgest_cytokine <- subset(gwas_catalog_filtered,gwas_catalog_filtered$Reported_trait %in%
                             "Midgestational cytokine/chemokine levels (maternal genetic effect)")



setwd("~/Documents/Bioinf/Git_BRB5/")

# these files I sent to Jura Barbitoff for annotation etc (it's LSEA input files)
#write.csv(diab_gest[,c("CHR","COORDINATE","RSID","REF","ALT","PVAL")],"diab_gest.csv",row.names = F)
#write.csv(preterm_birth[,c("CHR","COORDINATE","RSID","REF","ALT","PVAL")],"preterm_birth.csv",row.names = F)
#write.csv(placental_abrup[,c("CHR","COORDINATE","RSID","REF","ALT","PVAL")],"placental_abrup.csv",row.names = F)
#write.csv(preeclampsia[,c("CHR","COORDINATE","RSID","REF","ALT","PVAL")],"preeclampsia.csv",row.names = F)
#write.csv(midgest_cytokine[,c("CHR","COORDINATE","RSID","REF","ALT","PVAL")],"midgest_cytokine.csv",row.names = F)

#-----------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------
# UK Biobank and GWAS comparison
plot(venn(list("UK Biobank" = unique(ukb_total_lsea_filt$RSID),
                       "GWAS Catalog" = unique(gwas_catalog_filtered$RSID))),
             main = "UK Biobank            GWAS Catalog",
             fill = brewer.pal(3,"Set1"), alpha = 0.5, 
             edges = T, 
             lty = 1,
             lwd = 1.5, 
             labels = F, 
             legend = list(cex = 1.5), 
             quantities = list(cex = 2.5,font=1)) 

#-----------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------
# Making tables for a publication

# GWAS dataprocessing 
# Task - working with repeated between the phenotypes SNPs

rep_gwas_snp <- table(unique(gwas_catalog_filtered)[,c(1,11)]) %>% as.data.frame(.) %>% 
  filter(Freq != 1) %>% filter(Freq != 0) %>% dplyr::rename(rep_SNP = 1)
rep_gwas_snp$RSID <- gsub(rep_gwas_snp$rep_SNP,pattern = "-.*",replacement = "")
rep_gwas_snp <-plyr::join(rep_gwas_snp,gwas_catalog_filtered[,c("RSID","REF","ALT","COORDINATE","PVAL","Mapped_gene","Reported_trait","Trait(s)")],type="left")
colnames()
rep_gwas_snp <- 
  subset(gwas_catalog_filtered,Variant_and_risk_allele %in% rep_gwas_snp$rep_SNP) %>% 
  dplyr::select(RSID, REF, ALT, CHR,COORDINATE, PVAL,Mapped_gene,Reported_trait,Study_accession) %>% 
  plyr::join(.,rep_gwas_snp[,-1]) %>% dplyr::rename(Occurence_times_in_GwasCat = Freq) %>% 
  dplyr::arrange(RSID) %>% 
  filter(PVAL <= 1e-07)
# printing long table - no collapsing between repeats
#write.csv(rep_gwas_snp,"~/Documents/Bioinf/Git_BRB5/publication/repeated_GWAS_long_table.csv",row.names = F)

# collapsing repeats - making short table

rep_gwas_snp %>% 
  dplyr::group_by(RSID) %>% 
  dplyr::summarise(Reported_trait = paste(unique(Reported_trait), collapse = ", "),
                   Study_accession = paste(unique(Study_accession), collapse = ", ")) -> collapsed_rep

rep_gwas_snp_dedup <- rep_gwas_snp[!duplicated(rep_gwas_snp[c(1)]),][,-c(8,9)]
rep_gwas_snp_dedup <- plyr::join(rep_gwas_snp_dedup,collapsed_rep)

#write.csv(rep_gwas_snp_dedup,"~/Documents/Bioinf/Git_BRB5/publication/repeated_GWAS_short_table.csv",row.names = F)


# -----------
# UKB data processing (here we need to make tables for each phenotype)
total <- read.csv("total_ukbiobank_pregn.csv")
#View(table(total$variant)) # all SNPs are unique for each phenotype
# total <- plyr::join(total,preg_phen[,c("Phenotype_Code","n_cases","n_controls","h2_observed")] %>% dplyr::rename("Dataset"=Phenotype_Code)) %>% .[,-(1:2)]
# write.csv(total,"total_ukbiobank_pregn.csv",row.names = F)

total %>% 
  dplyr::filter(pval <= 1e-07) %>% 
  dplyr::select(-c(4:11)) %>% 
  dplyr::rename(PVAL = pval) -> total
total$CHR <- as.data.frame(str_split_fixed(total$variant,pattern = ":",n=2))[,1] %>% gsub(.,pattern = "X",replacement = 23)
total$COORDINATE <- as.data.frame(str_split_fixed(total$variant,pattern = ":",n=3))[,2]
total$variant <- total$variant %>% gsub("X","23",.) 
# https://docs.google.com/spreadsheets/d/1kvPoupSzsSFBNSztMzl04xMoSC3Kcx3CrjVf4yBmESU/edit#gid=227859291
# it's written that Minor allele (equal to ref allele when AF > 0.5, otherwise equal to alt allele).
# in out dataset all of the MAF < 0.5 that Minor allele could be REF
colnames(total)[2] <- "REF" 
total <- total %>% dplyr::select(-minor_AF) %>% dplyr::rename(UKB_dataset = Dataset) 
as.data.frame(str_split_fixed(total$variant,pattern = ":",n=Inf)) %>% dplyr::rename(L = V3,R = V4) %>% dplyr::select(L,R) %>% 
  cbind(.,total) -> total
total$ALT <- ifelse(as.character(total$REF)==as.character(total$L),as.character(total$R),as.character(total$L))
total %>% dplyr::select(-c(L,R)) -> total


# add mapping information from Yura (+- 50kb)
map_ukb <- fread('~/Documents/Bioinf/BRB5/UKB_intervals_gene_names/UKB_all.intervals_gene_names.tsv')
colnames(map_ukb) <- c("CHR","start","end","variants","mapped_elements")
map_ukb$CHR %>% gsub("X","23",.) -> map_ukb$CHR
map_ukb$variants %>% gsub("X","23",.) -> map_ukb$variants

total$mapped_elements <- pbsapply(total$variant,function(x){
  data <- subset(map_ukb,grepl(x,map_ukb$variants))
  return(data$mapped_elements)
})
total$mapped_elements %>% gsub("character\\(0\\)","NO",.)->total$mapped_elements 

write.table(total[,c("variant","CHR","REF","ALT","COORDINATE","PVAL","mapped_elements","UKB_dataset","n_cases","n_controls","h2_observed")],
            sep = "\t",row.names = F,file = "~/Documents/Bioinf/BRB5_GWAS_PREGNANCY/publication/ukb_all_phen_pval_07.tsv",quote = F)

#------------------------------------------------------------------------------------------------------
# add information with pval 1e-05
total <- read.csv("total_ukbiobank_pregn.csv")
#View(table(total$variant)) # all SNPs are unique for each phenotype
# total <- plyr::join(total,preg_phen[,c("Phenotype_Code","n_cases","n_controls","h2_observed")] %>% dplyr::rename("Dataset"=Phenotype_Code)) %>% .[,-(1:2)]
# write.csv(total,"total_ukbiobank_pregn.csv",row.names = F)

total %>% 
  dplyr::filter(pval <= 1e-05) %>% 
  dplyr::select(-c(4:11)) %>% 
  dplyr::rename(PVAL = pval) -> total
total$CHR <- as.data.frame(str_split_fixed(total$variant,pattern = ":",n=2))[,1] %>% gsub(.,pattern = "X",replacement = 23)
total$COORDINATE <- as.data.frame(str_split_fixed(total$variant,pattern = ":",n=3))[,2]
total$variant <- total$variant %>% gsub("X","23",.) 
# https://docs.google.com/spreadsheets/d/1kvPoupSzsSFBNSztMzl04xMoSC3Kcx3CrjVf4yBmESU/edit#gid=227859291
# it's written that Minor allele (equal to ref allele when AF > 0.5, otherwise equal to alt allele).
# in out dataset all of the MAF < 0.5 that Minor allele could be REF
colnames(total)[2] <- "REF" 
total <- total %>% dplyr::select(-minor_AF) %>% dplyr::rename(UKB_dataset = Dataset) 
as.data.frame(str_split_fixed(total$variant,pattern = ":",n=Inf)) %>% dplyr::rename(L = V3,R = V4) %>% dplyr::select(L,R) %>% 
  cbind(.,total) -> total
total$ALT <- ifelse(as.character(total$REF)==as.character(total$L),as.character(total$R),as.character(total$L))
total %>% dplyr::select(-c(L,R)) -> total


total$mapped_elements <- pbsapply(total$variant,function(x){
  data <- subset(map_ukb,grepl(x,map_ukb$variants))
  return(data$mapped_elements)
})
total <- apply(total,2,as.character)
write.table(total[,c("variant","CHR","REF","ALT","COORDINATE","PVAL","mapped_elements","UKB_dataset","n_cases","n_controls","h2_observed")],
            sep = "\t",row.names = F,file = "~/Documents/Bioinf/BRB5_GWAS_PREGNANCY/publication/ukb_all_phen_pval_05.tsv",quote = F)

  # dataset for doannotation
need_annotation <- subset(total,total$mapped_elements=="character(0)")
need_annotation %>% 
  dplyr::select(CHR,COORDINATE,REF,ALT,PVAL) ->need_annotation
write.table(need_annotation,"~/Downloads/need_annotation.tsv",sep = "\t")

# Printing all tables for each phenotypes

setwd("~/Documents/Bioinf/BRB5_GWAS_PREGNANCY/publication")
sapply(total$UKB_dataset,function(x){
  data <- subset(total,total$UKB_dataset==x)
  full_name = paste0("ukb_",noquote(x),".csv",collapse = "")
  write.csv(data[,c("variant","CHR","REF","ALT","COORDINATE","PVAL","mapped_elements","UKB_dataset","n_cases","n_controls","h2_observed")],
            full_name,row.names = F,quote = F)
})














