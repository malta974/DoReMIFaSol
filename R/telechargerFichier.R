#' Téléchargement des données sur le site de l'Insee
#'
#' @param donnees le nom des données que l'on souhaite télécharger sur le site de l'Insee, que l'on peut retrouver dans la table ([liste_donnees])
#' @param date optionnel : le millésime des données si nécessaire. Peut prendre le format YYYY ou encore DD/MM/YYYY ; dans le dernier cas, on prendra le premier jour de la période de référence.
#' @param telDir optionnel : le dossier dans lequel sont téléchargées les données brutes. Par défaut, un dossier temporaire de cache.
#' @param argsApi optionnel : dans le cas où c'est une API REST qui est utilisée, il est possible de spécifier des paramètres spécifiques à cette API de manière à collecter l'information désirée. Cf. [@details ].
#' 
#' @details 
#' La fonction permet de télécharger les données disponibles sur le site de l'Insee sous format csv, xls ou encore xlsx. Elle permet également, de manière expérimentale, de requêter certaines API REST de l'Insee ; ces services peuvent être repérés dans la table ([liste_donnees]) grâce à la variable `api_rest`.
#'
#' @return une liste contenant le résultat du téléchargement et les informations pour l'importation des données en R.
#' @export
#'
#' @examples \dontrun{
#' dl_bpe <- telechargerFichier(donnees = "BPE_ENS")
#' 
#' dl_rplog <- telechargerFichier("RP_LOGEMENT", date = "2016")
#' }
#' @importFrom utils download.file unzip read.csv tail
#' @export
telechargerFichier <- function(donnees, date=NULL, telDir=NULL, argsApi=NULL) {
  ## check the parameter donnees takes a valid value
  if (!donnees %in% ld$nom)
    stop("Le param\u00e8tre donnees est mal sp\u00e9cifi\u00e9, la valeur n'est pas r\u00e9f\u00e9renc\u00e9e")
  caract <- ld[ld$nom == donnees, ]
  ## check whether date is needed
  if (length(millesimesDisponibles(donnees)) > 1) {
    if (is.null(date)) stop("Il faut sp\u00e9cifier une date de r\u00e9f\u00e9rence pour ces donn\u00e9es.")
    if (nchar(date) == 4)
      select <- (format(caract$date_ref, "%Y") == as.character(date)) else
        select <- (caract$date_ref == as.Date(date, format = "%d/%m/%Y"))
      if (!any(select)) stop("La date sp\u00e9cifi\u00e9e n'est pas disponible.")
      if (sum(as.numeric(select), na.rm = TRUE) > 1) stop("Donn\u00e9es infra-annuelles a priori. Mieux sp\u00e9cifier la date de r\u00e9f\u00e9rence.")
      caract <- caract[which(select), ]
  }
  
  #dossier de téléchargement # si NULL aller dans le cache
  cache <- FALSE
  if (is.null(telDir)) {
    telDir <- ifelse(.Platform$OS.type == "windows", tempdir(), rappdirs::user_cache_dir())
    cache <- TRUE
  } else {
    if (!dir.exists(telDir))
      dir.create(telDir)
  }
  
  ## télécharge les fichiers csv, xls, xlsx...
  if (!caract$api_rest) {
    nomFichier <- file.path(dirname(telDir), basename(telDir), tail(unlist(strsplit(caract$lien, "/")), n=1L))
    if (!file.exists(nomFichier)) {
      dl <- tryCatch(download.file(url = caract$lien, destfile = nomFichier))
      if (cache)
        message("Aucun r\u00e9pertoire d'importation n'est d\u00e9fini. Les donn\u00e9es ont \u00e9t\u00e9 t\u00e9l\u00e9charg\u00e9es par d\u00e9faut dans le dossier: ", telDir)
    } else {
      dl <- 0
      message("Utilisation du cache")
    }
    
    if (caract$zip)
      fileArchive <- nomFichier else 
        fileArchive <- NULL
      
      if (caract$zip)
        fichierAImporter <- paste0(telDir, "/", caract$fichier_donnees) else
          fichierAImporter <- nomFichier
        
        if (caract$type == "csv") {
          argsImport <- list(file = fichierAImporter, delim = eval(parse(text = caract$separateur)), col_names = TRUE)
          if (!is.na(caract$encoding))
            argsImport[["locale"]] <- readr::locale(encoding = caract$encoding)
          if (!is.na(caract$valeurs_manquantes))
            argsImport[["na"]] <- unlist(strsplit(caract$valeurs_manquantes, "/"))
        }
        else if (caract$type == "xls") {
          argsImport <- list(path = fichierAImporter, skip = caract$premiere_ligne - 1, sheet = caract$onglet)
          if (!is.na(caract$derniere_ligne))
            argsImport[["n_max"]] <- caract$derniere_ligne - caract$premiere_ligne
          if (!is.na(caract$valeurs_manquantes))
            argsImport[["na"]] <- unlist(strsplit(caract$valeurs_manquantes, "/"))
        } else if (caract$type == "xlsx") {
          argsImport <- list(path = fichierAImporter, sheet = caract$onglet, skip = caract$premiere_ligne - 1)
        }
  } else {
    ## télécharge les données sur l'API
    token <- apinsee::insee_auth()
    if (!is.null(date))
      argsApi <- c(date = as.character(date), argsApi)
    if (is.null(argsApi$nombre)) {
      argsApi[["nombre"]] <- 0
      url <- httr::modify_url(caract$lien, query = argsApi)
      res <- httr::GET(url, httr::config(token = token), httr::write_memory())
      total <- httr::content(res)[[1]]$total
    } else {
      total <- argsApi[["nombre"]]
    }
    argsApi[["nombre"]] <- ifelse(total < 1000, total, 1000)
    if (is.null(argsApi[["tri"]]))
      argsApi[["tri"]] <- "siren"
    if (total > 1000)
      argsApi[["curseur"]] <- "*"
    nombrePages <- ceiling(total/1000)
    url <- httr::modify_url(caract$lien, query = argsApi)
    fichierAImporter <- paste0(telDir, "/", caract$nom, genererSuffixe(8), ".json")
    res <- httr::GET(url, httr::config(token = token), httr::write_disk(fichierAImporter), httr::progress())
    resultat <- res$status_code
    if (nombrePages > 1) {
      for (k in 2:nombrePages) {
        argsApi[["curseur"]] <-httr::content(res)$header$curseurSuivant
        url <- httr::modify_url(caract$lien, query = argsApi)
        fichierAImporter <- c(fichierAImporter, paste0(telDir, "/", caract$nom, "_", genererSuffixe(8), ".json"))
        res <- httr::GET(url, httr::config(token = token), httr::write_disk(tail(fichierAImporter, 1)), httr::progress())
        while (res$status_code == 429) {
          Sys.sleep(10)
          message("Nouvelle tentative...")
          res <- httr::GET(url, httr::config(token = token), httr::write_disk(tail(fichierAImporter, 1), overwrite = TRUE), httr::progress())
        }
        resultat <- c(resultat, res$status_code)
      }
    }
    dl <- NULL
    if (all(resultat == 200))
      dl <- 0
    argsImport <- list(fichier = fichierAImporter, nom = caract$nom)
    fileArchive <- NULL
  }
  return(list(result = dl, zip = caract$zip, big_zip = caract$big_zip, fileArchive = fileArchive, type = caract$type, argsImport = argsImport))
}

genererSuffixe <- function(longueur) {
  liste <- c(0:9, letters, LETTERS)
  s <- paste(sample(liste, longueur, replace = TRUE), collapse = "")
  return(s)
}
