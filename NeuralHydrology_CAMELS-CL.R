
require(dplyr)
require(readr)
require(tidyr)
require(data.table)
require(ggplot2)
require(patchwork)
require(lubridate)
require(hydroGOF)
require(Metrics)
require(stats)
require(ncdf4)
require(reticulate)
require(sf)
require(tools)
require(readr)

# rstudioapi::restartSession()
# 
# 
# usar DESDE esta version para compatibilizar el lenguaje del paquete.

use_python("C:/Users/.../AppData/Local/Programs/Python/Python310/python.exe", required = TRUE)
py_config()


#### INSTALAR NH EN LA CARPETA DE CAMELS ####


install_dir <- ".../LSTM_chile_cuencas"


if (!dir.exists(install_dir)) {
  dir.create(install_dir, recursive = TRUE)
}


setwd(install_dir)
cat("Directorio de instalación:", getwd(), "\n")

# # Verificar si Git está disponible
# git_check <- system("git --version", intern = TRUE) # si no esta hay que instalarlo y agregarlo al PATH

#
# system("git clone https://github.com/neuralhydrology/neuralhydrology.git") # clonar el repositorio para instalarlo
#

# Cambiar al directorio del repositorio
setwd(file.path(install_dir, "neuralhydrology"))
cat("Directorio del repositorio:", getwd(), "\n")

# Obtener la ruta del Python que usa reticulate
py_path <- reticulate::py_config()$python
cat("Usando Python de reticulate en:", py_path, "\n")

# Instalar NeuralHydrology en modo editable
system(paste0('"', py_path, '" -m pip install -e .'))

cat("\nVerificando instalación...\n")

reticulate::py_run_string("
import neuralhydrology
print('NeuralHydrology instalado en:', neuralhydrology.__file__)
")





# library(reticulate)
# 
# # Ruta al Python que reticulate está usando
# py_path <- reticulate::py_config()$python
# cat("Usando Python en:", py_path, "\n")
# 
# # Instalar los paquetes necesarios
# system(paste0('"', py_path, '" -m pip install matplotlib torch pandas pyyaml numpy xarray tqdm llvmlite numba ruamel tensorboard'))
# 
# 
# # Instalar los paquetes necesarios
# system(paste0('"', py_path, '" -m pip install tensorboard'))
# 
# cualquier paquete adicional que pida usar el nobmre que pide y la misma linea de codigo para instalar





#### MODELOS NEURAL HYDROLOGY - PREPROCESAMIENTO DATOS CAMELS CL #########



q_file      <- ".../LSTM_chile_cuencas/CAMELS_CL_v202201/q_mm_day.csv"
precip_file <- ".../LSTM_chile_cuencas/CAMELS_CL_v202201/precip_mm_day.csv"
pet_file    <- ".../LSTM_chile_cuencas/CAMELS_CL_v202201/pet_mm_day.csv"
tmin_file   <- ".../LSTM_chile_cuencas/CAMELS_CL_v202201/tmin_day.csv"
tmax_file   <- ".../LSTM_chile_cuencas/CAMELS_CL_v202201/tmax_day.csv"


q_df      <- read_csv(q_file)
precip_df <- read_csv(precip_file)
pet_df    <- read_csv(pet_file)
tmin_df   <- read_csv(tmin_file)
tmax_df   <- read_csv(tmax_file)


print_head <- function(df, name) {
  cat(paste0("\n===== Primeras filas de ", name, " =====\n"))
  print(df[1:2, ])
}


crear_csv_por_cuenca <- function(input_dir, output_dir) {
  # Crear carpeta de salida si no existe
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Leer archivos
  q_df      <- read_csv(file.path(input_dir, "q_mm_day.csv"), show_col_types = FALSE)
  precip_df <- read_csv(file.path(input_dir, "precip_mm_day.csv"), show_col_types = FALSE)
  pet_df    <- read_csv(file.path(input_dir, "pet_mm_day.csv"), show_col_types = FALSE)
  tmin_df   <- read_csv(file.path(input_dir, "tmin_day.csv"), show_col_types = FALSE)
  tmax_df   <- read_csv(file.path(input_dir, "tmax_day.csv"), show_col_types = FALSE)

  # Obtener fechas comunes
  fechas <- Reduce(function(x, y) inner_join(x, y, by = "date"),
                   list(dplyr::select(q_df, date),
                        dplyr::select(precip_df, date),
                        dplyr::select(pet_df, date),
                        dplyr::select(tmin_df, date),
                        dplyr::select(tmax_df, date)))

  # Obtener lista de cuencas (columnas excluyendo metadata)
  cuencas <- setdiff(names(q_df), c("date", "year", "month", "day"))

  # Iterar sobre cada cuenca
  for (cuenca in cuencas) {
    # Extraer columnas de cada variable para la cuenca
    df_cuenca <- fechas %>%
      left_join(dplyr::select(q_df, date, !!cuenca) %>% rename(q_mm = !!cuenca), by = "date") %>%
      left_join(dplyr::select(precip_df, date, !!cuenca) %>% rename(precip_mm = !!cuenca), by = "date") %>%
      left_join(dplyr::select(pet_df, date, !!cuenca) %>% rename(pet_mm = !!cuenca), by = "date") %>%
      left_join(dplyr::select(tmin_df, date, !!cuenca) %>% rename(tmin = !!cuenca), by = "date") %>%
      left_join(dplyr::select(tmax_df, date, !!cuenca) %>% rename(tmax = !!cuenca), by = "date") %>%
      arrange(date)

    # Reemplazar NA con -9999
    df_cuenca[is.na(df_cuenca)] <- -9999

    # Escribir archivo CSV con coma como separador
    output_file <- file.path(output_dir, paste0(cuenca, ".csv"))
    write_csv(df_cuenca, output_file, na = "-9999")
  }

  message("Todos los archivos han sido generados en: ", output_dir)
}


input_dir <- ".../LSTM_chile_cuencas/CAMELS_CL_v202201"
output_dir <- file.path(input_dir, "preprocessed")

crear_csv_por_cuenca(input_dir, output_dir)


# CONVERTIR NC TIMES_SERIES

convert_csv_to_netcdf <- function(csv_path, output_dir) {
  # Leer el archivo CSV
  data <- read.csv(csv_path)
  
  # Asegurarse de que la columna de fechas esté correctamente formateada
  data$date <- as.Date(data$date, format="%Y-%m-%d")
  
  # Obtener el nombre del archivo sin extensión
  file_name <- tools::file_path_sans_ext(basename(csv_path))
  
  # Definir las dimensiones del NetCDF
  time_vals <- as.numeric(difftime(data$date, as.Date("1900-01-01"), units = "days"))
  date <- ncdim_def(name = "date", units = "days since 1900-01-01", vals = time_vals)
  
  # Definir las variables del NetCDF
  var_defs <- lapply(names(data)[-1], function(var_name) {
    ncvar_def(name = var_name, units = "unknown", dim = date, missval = -9999)
  })
  
  # Crear el archivo NetCDF
  nc_file <- file.path(output_dir, paste0(file_name, ".nc"))
  nc <- nc_create(nc_file, var_defs)
  
  # Escribir los datos en el archivo NetCDF
  for (i in 2:ncol(data)) {
    ncvar_put(nc, var_defs[[i - 1]], data[[i]])
  }
  
  # Cerrar el archivo NetCDF
  nc_close(nc)
  
  return(nc_file)
}

# Directorio de entrada y salida
input_dir <- ".../LSTM_chile_cuencas/CAMELS_CL_v202201/preprocessed"
output_dir <- ".../LSTM_chile_cuencas/CAMELS_CL_v202201/time_series"

# Crear el directorio de salida si no existe
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Convertir todos los archivos CSV en el directorio de entrada
csv_files <- list.files(input_dir, pattern = "\\.csv$", full.names = TRUE)
lapply(csv_files, convert_csv_to_netcdf, output_dir = output_dir)




# ATRIBUTOS ESTATICOS 

input_file  <- ".../LSTM_chile_cuencas/CAMELS_CL_v202201/catchment_attributes.csv"
output_dir  <- ".../LSTM_chile_cuencas/CAMELS_CL_v202201/attributes"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)


# Leer las líneas del archivo
raw_lines <- read_lines(input_file)

# Eliminar las comillas dobles envolventes de cada línea (si existen)
cleaned_lines <- gsub('^"|"$', '', raw_lines)

# Convertir a un objeto tipo archivo en memoria
cleaned_csv <- I(paste(cleaned_lines, collapse = "\n"))

# Ahora leer el CSV correctamente
catchment_attributes <- read_csv(cleaned_csv)


names(catchment_attributes) <- gsub('\"', '', names(catchment_attributes))  # quita todas las comillas dobles
names(catchment_attributes) <- gsub('\\s+$', '', names(catchment_attributes))  # elimina espacios al final
names(catchment_attributes) <- gsub('+$', '', names(catchment_attributes))  # por si hay signos extraños

catchment_attributes$gauge_name <- gsub('"', '', catchment_attributes$gauge_name)
catchment_attributes$geol_class_1st <- gsub('"', '', catchment_attributes$geol_class_1st)
catchment_attributes$geol_class_2nd <- gsub('"', '', catchment_attributes$geol_class_2nd)

catchment_attributes$lc_dom_name <- gsub('"', '', catchment_attributes$lc_dom_name)

View(catchment_attributes)


guardar_cuencas_csv <- function(data, output_dir) {
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  
  # Asegurarnos de que exista la columna gauge_id
  if (!"gauge_id" %in% names(data)) {
    stop("La columna 'gauge_id' no existe en los datos")
  }
  
  # Iterar por cada fila/cuenca
  for (i in seq_len(nrow(data))) {
    fila <- data[i, , drop = FALSE]
    gauge_id <- fila$gauge_id
    file_path <- file.path(output_dir, paste0(gauge_id, ".csv"))
    
    write.table(
      fila,
      file = file_path,
      sep = ",",
      row.names = FALSE,
      col.names = TRUE,
      quote = TRUE,      # Fuerza comillas en todo
      na = "NA",
      qmethod = "double"
    )
  }
  
  message(" Archivos generados en: ", output_dir)
}


guardar_cuencas_csv(catchment_attributes, output_dir)


#### TRAIN TEST EVAL CUENCAS #### 

# INCLUIR O EXCLUIR ID DE CUENCAS, NOTAR QUE ESCRIBE LAS MISMAS CUENCAS PARA TRAIN TEST EVAL...
escribir_ids_a_txt <- function(catchment_attributes, output_dir) {
  # Leer archivo de atributos
  atributos <- catchment_attributes

  # Asegurar que gauge_id sea carácter
  ids <- as.character(atributos$gauge_id)

  # IDs a excluir
  ids_excluir <- c(
    '10122002','10122003','10133000','10313001','10322003','10343002','10344003','10344004','10405005','10411003','10683002',
    '11500002','11532000','12285003','12286002','12288002','12288003','12288004','12289003','12291001','12400003','12400004',
    '12561001','12563001','12660001','12820001','12825002','12861001','12863002','12865001','12872001','12876004','12930001',
    '1300009','1502008','1610004','2103003','2104013','2110001','2110031','4306001','4314001','4501002','4502001','4502002',
    '4506002','4511001','4515001','4516001','4522001','4523001','4531001','4534001','4535002','4540001','4540002','4550003',
    '4556001','4703001','4716001','4810005','4810006','5101002','5221001','5401002','5402015','5403003','5405001','5406002',
    '5410001','5411002','5415002','5420002','5421001','5423002','5423004','5423006','5427003','5715001','5720001','5721016',
    '6000003','6033011','6034001','6034022','6034023','7102001','7104001','7200002','7331001','7340001','7350002','7351001',
    '7354001','7355001','7355003','8115001','8117001','8117008','8133001','8140002','8210003','8220008','8220009','8220010',
    '8308000','8316002','8317004','8317005','8319001','8324002','8350001','8366002','8380006','8381003','8386001','8393002',
    '8530001','8700002','8700003','8720001','8821001','8821003','8821006','8822001','9107002','9111001','9400000','9423001'
  )

  # Filtrar
  ids_filtrados <- ids[!ids %in% ids_excluir]

  # Definir rutas
  rutas <- c(
    train = file.path(output_dir, "train.txt"),
    test  = file.path(output_dir, "test.txt"),
    eval  = file.path(output_dir, "eval.txt")
  )

  # Escribir
  for (ruta in rutas) {
    write_lines(ids_filtrados, ruta)
  }

  message("Archivos escritos (sin los IDs excluidos): ", paste(rutas, collapse = ", "))
}


output_dir <- ".../LSTM_chile_cuencas/LSTM"

# Ejecutar la función
escribir_ids_a_txt(catchment_attributes, output_dir)



#### MODELOS NEURAL HYDROLOGY LSTM - ENTRENAMIENTO Y VALIDACION #########


# desinstalar e instalar por si se le genera una modificacion al codigo fuente del paquete ya instalado.
# system("pip uninstall neuralhydrology --yes")
# 
# 
# system("pip install -e .")


py_run_string("
import pickle
from pathlib import Path
import matplotlib.pyplot as plt
import torch
from neuralhydrology.evaluation import metrics
from neuralhydrology.nh_run import start_run, eval_run
from neuralhydrology.datasetzoo.basedataset import BaseDataset
from neuralhydrology.utils.config import Config
from neuralhydrology.datasetzoo.genericdataset import GenericDataset
from neuralhydrology.modelzoo.__init__ import get_model

# Comprueba si hay GPU disponible
config_file = Path('C:/Otono_2024/LSTM_chile_cuencas/LSTM/EA_LSTM_1.yaml')
if torch.cuda.is_available():
    start_run(config_file=config_file)
else:
    start_run(config_file=config_file, gpu=-1)
")


# HABEMUS DEEP CUENQUITA



#### GRAFICOS DE PERDIDA ####


ruta_base = ".../LSTM_chile_cuencas/LSTM/RUN_EALSTM"


evaluar_modelo_nh <- function(nombre_modelo, epoca, ruta_base) {
  # Rutas base
  ruta_base <- ruta_base
  ruta_log <- file.path(ruta_base, nombre_modelo, "output.log")
  ruta_modelo <- file.path(ruta_base, nombre_modelo)
  ruta_test <- file.path(ruta_modelo, "test", sprintf("model_epoch%03d", epoca))
  
  # Validación
  if (!file.exists(ruta_log)) {
    stop(paste("No se encontró el archivo:", ruta_log))
  }
  
  # Leer log y extraer avg_loss
  lineas_log <- readLines(ruta_log)
  lineas_loss <- grep("Epoch .* average loss: avg_loss:", lineas_log, value = TRUE)
  epoch <- as.numeric(gsub(".*Epoch ([0-9]+).*", "\\1", lineas_loss))
  avg_loss <- as.numeric(gsub(".*avg_loss: ([0-9.]+),.*", "\\1", lineas_loss))
  df_loss <- data.frame(Epoch = epoch, Avg_Loss = avg_loss)
  
  plot_loss <- ggplot(df_loss, aes(x = Epoch, y = Avg_Loss)) +
    geom_line(color = "steelblue", size = 1) +
    geom_point(color = "darkred", size = 2) +
    labs(
      title = paste("Evolución del Loss Promedio por Epoch\nModelo:", nombre_modelo),
      x = "Epoch",
      y = "Loss Promedio"
    ) +
    theme_minimal() +
    theme(
      panel.border = element_rect(color = "black", fill = NA, size = 1)
    )
  
  print(plot_loss)
  
  # Ejecutar eval_run en periodo test
  py_run_string(sprintf("
import pickle
from pathlib import Path
from neuralhydrology.nh_run import eval_run
run_dir = Path(r'%s')
eval_run(run_dir=run_dir, period='test', epoch=%d)
", ruta_modelo, epoca))
  message("Evaluación del modelo completada: ", nombre_modelo)

  
  # Leer métricas del test
  ruta_csv <- file.path(ruta_test, "test_metrics.csv")
  if (!file.exists(ruta_csv)) stop("No se encontró test_metrics.csv")
  df_metrics <- read.csv(ruta_csv)
  
  # Leer resultados pickle
  ruta_pickle <- file.path(ruta_test, "test_results.p")
  if (!file.exists(ruta_pickle)) stop("No se encontró test_results.p")
  
  pickle <- import("pickle")
  builtins <- import_builtins()
  f <- builtins$open(ruta_pickle, "rb")
  resultados_p <- pickle$load(f)
  f$close()
  
  # Retornar resultados en lista
  return(list(
    plot_loss = plot_loss,
    loss_data = df_loss,
    metrics = df_metrics,
    test_results = resultados_p
  ))
}

test = evaluar_modelo_nh('test_LSTM_3009_001717', 10, ruta_base)

test$test_results

test$plot_loss



# Vector de avg_total_loss para las primeras 10 épocas
avg_total_loss <- c(
  0.19077,  # Epoch 1
  0.14658,  # Epoch 2
  0.12509,  # Epoch 3
  0.11616,  # Epoch 4
  0.10968,  # Epoch 5
  0.10543,  # Epoch 6
  0.10454,  # Epoch 7
  0.10064,  # Epoch 8
  0.09803,  # Epoch 9
  0.09743   # Epoch 10
)


# Crear data.frame con epoch y avg_total_loss
df_loss <- data.frame(
  Epoch = 1:10,
  Avg_Total_Loss = avg_total_loss
)



loss = ggplot(df_loss, aes(x = Epoch, y = Avg_Total_Loss)) +
  geom_line(color = "black", size = 1) +
  geom_point(color = "black", size = 2) +
  labs(
    title = "Pérdida Total Promedio por Época",
    x = "Época",
    y = "Pérdida Total Promedio (mm²/d²)"
  ) +
  scale_x_continuous(breaks = seq(0, 10, by = 2)) +  # Mostrar cada 2 épocas
  theme_minimal() +
     theme(
        legend.position = "bottom",
        legend.title    = element_text(size = 14),
        legend.text     = element_text(size = 12, face = "bold"),
        plot.title      = element_text(hjust = 0.5, size = 18, face = "bold"),
        panel.border    = element_rect(color = "black", fill = NA, size = 2),
        axis.text.x     = element_text( face = "bold", size = 16),
        axis.text.y     = element_text(face = "bold", size = 16), 
        axis.title.y    = element_text(face = "bold", size = 16),
        axis.title.x    = element_text(face = "bold", size = 16),
        strip.text      = element_text(size = 12, face = "bold")
      )


file_path <- "C:/GITHUB/LSTM_CUENCAS/perdida.png"


width_px <- 780
height_px <- 514

dpi <- 96

ggsave(
  filename = file_path,
  plot = loss ,
  width = width_px,
  height = height_px,
  units = "px",
  dpi = dpi,
  bg = "white"  
)

print(paste("Plot saved to:", file_path))




#### MODELOS NEURAL HYDROLOGY LSTM - TEST #########


# PARA UNA CUENCA 

graficar_cuenca_diario <- function(resultados_modelo, cuenca_id) {
  resultados_p <- resultados_modelo$test_results
  
  if (!(cuenca_id %in% names(resultados_p))) {
    stop(paste("Cuenca", cuenca_id, "no se encuentra en los resultados."))
  }
  
  xr_dataset <- resultados_p[[cuenca_id]]$`1D`$xr
  
  # Extraer variables
  fechas <- as.Date(xr_dataset$date$values)
  p_obs <- as.numeric(xr_dataset$q_mm_obs$values[, 1])
  p_sim <- as.numeric(xr_dataset$q_mm_sim$values[, 1])
  
  # Extraer NSE y KGE si están disponibles
  NSE <- resultados_p[[cuenca_id]]$`1D`$NSE
  KGE <- resultados_p[[cuenca_id]]$`1D`$KGE
  
  # Validación
  stopifnot(length(fechas) == length(p_obs), length(p_obs) == length(p_sim))
  
  df <- data.frame(
    fecha = fechas,
    Observado = p_obs,
    Simulado = p_sim
  )
  
  # Convertir a formato largo para la serie temporal
  df_long <- pivot_longer(df, cols = c("Observado", "Simulado"),
                          names_to = "Tipo", values_to = "Valor")
  
  # Paleta de colores personalizada
  colores <- c("Observado" = "black", "Simulado" = "red")
  
  # Crear título con rango de fechas + NSE y KGE
  titulo <- paste0(
    "Cuenca ", cuenca_id, 
    ", Periodo Testeo: ", format(min(fechas), "%Y-%m-%d"), " a ", format(max(fechas), "%Y-%m-%d"),
    "\nNSE = ", round(NSE, 3), " | KGE = ", round(KGE, 3)
  )
  
  # Gráfico 1: Serie temporal
  g1 <- ggplot(df_long, aes(x = fecha, y = Valor, color = Tipo)) +
    geom_line() +
    scale_color_manual(values = colores) +
    labs(title = titulo,
         x = "Fecha", y = "Q diario (mm/d)", color = "Leyenda") +
    theme_minimal() +
      theme(
        legend.position = "bottom",
        legend.title    = element_text(size = 14),
        legend.text     = element_text(size = 12, face = "bold"),
        plot.title      = element_text(hjust = 0.5, size = 18, face = "bold"),
        panel.border    = element_rect(color = "black", fill = NA, size = 2),
        axis.text.x     = element_text(face = "bold", size = 16),
        axis.text.y     = element_text(face = "bold", size = 16), 
        axis.title.y    = element_text(face = "bold", size = 16),
        axis.title.x    = element_text(face = "bold", size = 16),
        strip.text      = element_text(size = 12, face = "bold")
      )

  
  # Gráfico 2: Dispersión
  df_disp <- na.omit(data.frame(Observado = p_obs, Simulado = p_sim))
  
  g2 <- ggplot(df_disp, aes(x = Observado, y = Simulado)) +
    geom_point(alpha = 0.5, color = "black") +
    geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed") +
    coord_equal() +
    labs(title = paste("Dispersión Simulados y Observados"),
         x = "Q Observado (mm/d)", y = "Q Simulado (mm/d)") +
    theme_minimal() +
     theme(
        legend.position = "bottom",
        legend.title    = element_text(size = 14),
        legend.text     = element_text(size = 12, face = "bold"),
        plot.title      = element_text(hjust = 0.5, size = 18, face = "bold"),
        panel.border    = element_rect(color = "black", fill = NA, size = 2),
        axis.text.x     = element_text(face = "bold", size = 16),
        axis.text.y     = element_text(face = "bold", size = 16), 
        axis.title.y    = element_text(face = "bold", size = 16),
        axis.title.x    = element_text(face = "bold", size = 16),
        strip.text      = element_text(size = 12, face = "bold")
      )
    
  
  # Mostrar en panel lado a lado
  panel <- g1 + g2 + plot_layout(ncol = 2, guides = "collect") & theme(legend.position = 'bottom')

  return(panel)
}

diario = graficar_cuenca_diario(test, "8910001")



# PARA TODAS 


graficar_dispersion_q_diario_todas_cuencas <- function(resultados_modelo) {
  resultados_p <- resultados_modelo$test_results
  cuencas <- names(resultados_p)
  
  todos_obs <- c()
  todos_sim <- c()
  todas_fechas <- c()
  kge_values <- c()
  
  for (cuenca_id in cuencas) {
    xr_dataset <- resultados_p[[cuenca_id]]$`1D`$xr
    
    fechas <- as.Date(xr_dataset$date$values)
    obs <- as.numeric(xr_dataset$q_mm_obs$values[, 1])
    sim <- as.numeric(xr_dataset$q_mm_sim$values[, 1])
    
    todos_obs <- c(todos_obs, obs)
    todos_sim <- c(todos_sim, sim)
    todas_fechas <- c(todas_fechas, fechas)
    
    # Extraer KGE si existe, y almacenarlo
    if (!is.null(resultados_p[[cuenca_id]]$`1D`$KGE)) {
      kge_values <- c(kge_values, resultados_p[[cuenca_id]]$`1D`$KGE)
    }
  }
  
  df_all <- na.omit(data.frame(Observado = todos_obs, Simulado = todos_sim))
  
  r <- cor(df_all$Observado, df_all$Simulado)
  r2 <- r^2
  
  # Calcular KGE globalmente (sin importar valores almacenados)
  mean_obs <- mean(df_all$Observado)
  mean_sim <- mean(df_all$Simulado)
  sd_obs <- sd(df_all$Observado)
  sd_sim <- sd(df_all$Simulado)
  
  kge_global <- 1 - sqrt((r - 1)^2 + (sd_sim / sd_obs - 1)^2 + (mean_sim / mean_obs - 1)^2)
  
  # Solo promedio de KGE si existen valores; si no, NA
  if(length(kge_values) > 0) {
    kge_promedio <- mean(kge_values, na.rm = TRUE)
  } else {
    kge_promedio <- NA
  }
  
  # Formatear valores para texto: mostrar kge_global calculado
  r2_val <- ifelse(is.na(r2) || is.nan(r2), "NA", sprintf("%.3f", r2))
  kge_val <- ifelse(is.na(kge_global) || is.nan(kge_global), "NA", sprintf("%.3f", kge_global))
  
  fecha_min <- min(todas_fechas, na.rm = TRUE)
  fecha_max <- max(todas_fechas, na.rm = TRUE)
  
  fecha_min_date <- as.Date(fecha_min, origin = "1970-01-01")
  fecha_max_date <- as.Date(fecha_max, origin = "1970-01-01")
  
  fecha_ini <- format(fecha_min_date, "%Y-%m-%d")
  fecha_fin <- format(fecha_max_date, "%Y-%m-%d")
  
  subtitle_text <- paste0("R2 = ", r2_val, " | KGE = ", kge_val, " | Periodo: ", fecha_ini, " a ", fecha_fin)
  print(subtitle_text)
  
  g <- ggplot(df_all, aes(x = Observado, y = Simulado)) +
    geom_point(alpha = 0.3, color = "black") +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red", size = 1.2) +
    coord_equal() +
    labs(
      title = "Dispersión en Periodo de Testeo - Región del Bíobio",
      subtitle = subtitle_text,
      x = "Q Observado (mm/d)",
      y = "Q Simulado (mm/d)"
    ) +
    theme_minimal() +
     theme(
        legend.position = "bottom",
        legend.title    = element_text(size = 14),
        legend.text     = element_text(size = 12, face = "bold"),
        plot.title      = element_text(hjust = 0.5, size = 18, face = "bold"),
        plot.subtitle   = element_text(hjust = 0.5, size = 18, face = "bold"),
        panel.border    = element_rect(color = "black", fill = NA, size = 2),
        axis.text.x     = element_text( face = "bold", size = 16),
        axis.text.y     = element_text(face = "bold", size = 16), 
        axis.title.y    = element_text(face = "bold", size = 16),
        axis.title.x    = element_text(face = "bold", size = 16),
        strip.text      = element_text(size = 12, face = "bold")
      )
    
  
  return(g)
}

todos = grafico_dispersion_q <- graficar_dispersion_q_diario_todas_cuencas(test)


print(grafico_dispersion_q)





file_path <- "C:/GITHUB/LSTM_CUENCAS/diario.png"

width_px <- 1270
height_px <- 714

dpi <- 96

ggsave(
  filename = file_path,
  plot = diario ,
  width = width_px,
  height = height_px,
  units = "px",
  dpi = dpi,
  bg = "white"  
)

print(paste("Plot saved to:", file_path))






file_path <- "C:/GITHUB/LSTM_CUENCAS/todos.png"

width_px <- 780
height_px <- 514

dpi <- 96

ggsave(
  filename = file_path,
  plot = todos ,
  width = width_px,
  height = height_px,
  units = "px",
  dpi = dpi,
 bg = "white"  
)

print(paste("Plot saved to:", file_path))


