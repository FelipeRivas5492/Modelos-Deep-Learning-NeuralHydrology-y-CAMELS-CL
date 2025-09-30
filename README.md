
<strong> MODELOS DEEP LEARNING: NEURALHYDROLOGY Y CAMELS-CL. DISPONIBLES EN:</strong>

<p align="justify">
<strong>Kratzert, F., Gauch, M., Nearing, G., & Klotz, D. (2022). NeuralHydrology — A Python library for deep learning research in hydrology. Journal of Open Source Software, 7(71), 4050. https://doi.org/10.21105/joss.04050 </strong>
</p>

<p align="justify">
<strong>Alvarez-Garreton, C., Mendoza, P. A., Boisier, J. P., Addor, N., Galleguillos, M., Zambrano-Bigiarini, M., Lara, A., Puelma, C., Cortes, G., Garreaud, R., McPhee, J., and Ayala, A.: The CAMELS-CL dataset: catchment attributes and meteorology for large sample studies – Chile dataset, Hydrol. Earth Syst. Sci. Discuss., https://doi.org/10.5194/hess-2018-23, in review, 2018. </strong>
</p>

<p align="justify">
1. El código es una implementación para correr desde RStudio el paquete NeuralHydrology, escrito en lenguaje Python. Para ello, se usó el paquete Reticulate y se generaron funciones para pre-procesar la base de datos de CAMELS-CL como una base de datos generica y con ello evitar errores de incompatibilidad entre el formato de la base de datos y algunas funciones del paquete. Se generó un entrenamiento para las cuencas de la Región del Biobío para un modelo EA-LSTM y los siguientes atributos dinámicos y estáticos:


**Dinámicos:**
- precip_mm
- pet_mm
- tmin
- tmax

**Estáticos:**
- mean_elev
- mean_slope_perc
- gauge_lat
- gauge_lon
- aridity_cr2met_1979_2010
</p>

Los hiperparámetros se pueden ver en el archivo YAML, además de todas las especificaciones del modelo implementado. 


<div align="center">
  <img src="https://raw.githubusercontent.com/FelipeRivas5492/Modelos-Deep-Learning-NeuralHydrology-y-CAMELS-CL/edit/main/FIG.png" alt="Figura 1 - fig1">
</div>
<p><strong>Figura 1</strong>: fig1.</p>
