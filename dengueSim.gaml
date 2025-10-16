model DengueSim

/* 
 * MODELO DE SIMULAÇÃO DA DENGUE - SANTO AMARO/SP
 * Autores: Henrique Kioshi Yamauchi | Renato Jorge Alpalhão
 */

global {
    // === DADOS CLIMÁTICOS SANTO AMARO ===
    float temperatura_externa <- 26.8;
    float precipitacao <- 8.5;
    float umidade <- 75.0;
    
    // === PARÂMETROS EPIDEMIOLÓGICOS ===
    float prob_transmissao_hum_mos <- 0.35;  // Aumentada para clima tropical
    float prob_transmissao_mos_hum <- 0.45;  // Aumentada para Santo Amaro
    int tempo_incubacao_mosquito <- 4;       // Mais rápido em clima quente
    
    // === COORDENADAS SANTO AMARO ===
    geometry santo_amaro_boundary <- envelope({-46.720, -23.660, -46.680, -23.620});
    point centro_santo_amaro <- {-46.700, -23.640};
    
    // === MÉTRICAS ===
    int total_infectados_h <- 0;
    int total_recuperados <- 0;
    float r0_instantaneo <- 0.0;
    int ciclo_dia <- 0;
    
    // === DADOS EXTERNOS ===
    file dados_externos <- file("../data/clima_santo_amaro.csv");
    
    // === LISTAS ===
    list<point> criadouros_potenciais <- [];
    list<string> bairros_vizinhos <- ["Socorro", "Jardim São Luís", "Campo Belo", "Jurubatuba"];
    
    // === ESPÉCIES DE ÁREAS ===
    species area_risco {
        string nome;
        geometry geometria;
        int nivel_risco; // 1-5
        int casos_reportados <- 0;
        
        aspect visual {
            draw geometria color:
                nivel_risco = 5 ? #red :
                nivel_risco = 4 ? #orange :
                nivel_risco = 3 ? #yellow :
                nivel_risco = 2 ? #lightgreen : #green;
            border #black;
        }
    }
    
    // === INICIALIZAÇÃO SANTO AMARO ===
    init {
        write "🔄 Iniciando simulação em Santo Amaro, Zona Sul de SP...";
        
        // 1. CRIAR ÁREAS DE RISCO EM SANTO AMARO
        create area_risco with: [ 
            new area_risco(nome: "Centro Santo Amaro", geometria: circle(800) at: centro_santo_amaro, nivel_risco: 4),
            new area_risco(nome: "Margens Pinheiros", geometria: circle(600) at: {-46.710, -23.635}, nivel_risco: 5),
            new area_risco(nome: "Jardim Santo Amaro", geometria: circle(700) at: {-46.695, -23.645}, nivel_risco: 3),
            new area_risco(nome: "Vila Socorro", geometria: circle(500) at: {-46.690, -23.655}, nivel_risco: 4)
        ];
        
        // 2. CRIAR HUMANOS - 100 RESIDENTES
        create humanos number: 100 {
            location <- any_location_in(santo_amaro_boundary);
            localizacao_casa <- location;
            // Trabalhos típicos da região: comércio, serviços, indústria
            localizacao_trabalho <- location + {rnd(-2000.0, 2000.0), rnd(-2000.0, 2000.0)};
            area_residencia <- one_of(area_risco covering (location));
        }
        
        // 3. CRIAR MOSQUITOS - 100 INICIAIS
        create mosquitos number: 100 {
            location <- any_location_in(santo_amaro_boundary);
            criadouro <- location;
        }
        
        // 4. CRIADOUROS TÍPICOS DE SANTO AMARO
        // Áreas com maior risco: margens do rio, terrenos baldios, etc.
        loop i from: 1 to: 20 {
            point criadouro <- any_location_in(santo_amaro_boundary);
            // Maior concentração nas áreas de risco 4-5
            area_risco area <- one_of(area_risco where (each.nivel_risco >= 4));
            if (area != nil) {
                criadouro <- any_location_in(area.geometria);
            }
            criadouros_potenciais <- criadouros_potenciais + [criadouro];
        }
        
        // 5. CASOS INICIAIS - 3 PRIMEIROS CASOS
        loop i from: 1 to: 3 {
            ask one_of(humanos where (each.area_residencia.nivel_risco >= 4)) {
                infectado <- true;
                dias_infeccao <- 1;
                area_residencia.casos_reportados <- area_residencia.casos_reportados + 1;
            }
        }
        
        write "🎯 Santo Amaro: 100 residentes, 100 mosquitos, 3 casos iniciais";
        write "📍 Áreas de risco mapeadas: Centro, Margens Pinheiros, Jardim SA, Vila Socorro";
    }
    
    // === ATUALIZAÇÃO DE DADOS CLIMÁTICOS REAIS ===
    reflex atualizar_dados_externos {
        ciclo_dia <- cycle % 24; // Hora do dia virtual
        
        // Simulação de variação diária de temperatura em Santo Amaro
        temperatura_externa <- 26.8 + (sin(ciclo_dia / 24.0 * 360.0) * 4.0);
        
        if (exists(dados_externos)) {
            list<string> linhas <- read(dados_externos);
            if (length(linhas) > 1) {
                list<string> dados <- split(linhas[1], ",");
                if (length(dados) >= 3) {
                    // Usa dados reais se disponíveis, senão mantém simulação
                    temperatura_externa <- float(dados[0]);
                    precipitacao <- float(dados[1]);
                    umidade <- float(dados[2]);
                }
            }
        }
        
        // Chuva mais frequente no verão em Santo Amaro
        if (flip(0.3)) { // 30% chance de chuva
            precipitacao <- rnd(5.0, 25.0);
        } else {
            precipitacao <- rnd(0.0, 3.0);
        }
    }
    
    // === ATUALIZAÇÃO DE MÉTRICAS ===
    reflex atualizar_metricas {
        total_infectados_h <- count(humanos where (each.infectado));
        total_recuperados <- count(humanos where (each.recuperado));
        
        int novos_casos <- count(humanos where (each.infectado and each.dias_infeccao == 1));
        int susceptiveis <- count(humanos where (not each.infectado and not each.recuperado));
        
        r0_instantaneo <- (novos_casos > 0 and susceptiveis > 0) ? 
                          (float(novos_casos) / float(suscceptiveis)) * 8.0 : 0.0;
    }
}

// === ESPÉCIE HUMANOS - RESIDENTES SANTO AMARO ===
species humanos skills: [moving] {
    // Estados de saúde
    bool infectado <- false;
    bool recuperado <- false;
    int dias_infeccao <- 0;
    bool imune <- false;
    
    // Mobilidade em Santo Amaro
    point localizacao_casa <- location;
    point localizacao_trabalho <- location + {rnd(-3000.0, 3000.0), rnd(-3000.0, 3000.0)};
    bool em_casa <- true;
    
    // Características individuais
    float susceptibilidade <- rnd(0.6, 1.0);
    int tempo_recuperacao <- rnd(5, 8);
    
    // Integração geográfica
    area_risco area_residencia;
    bool usa_transporte_publico <- flip(0.7); // Alta uso de transporte em SP
    
    // === COMPORTAMENTOS TÍPICOS SANTO AMARO ===
    reflex atualizar_saude {
        if (infectado) {
            dias_infeccao <- dias_infeccao + 1;
            if (dias_infeccao > tempo_recuperacao) {
                infectado <- false;
                recuperado <- true;
                imune <- flip(0.8);
                area_residencia.casos_reportados <- max(0, area_residencia.casos_reportados - 1);
            }
        }
    }
    
    reflex mover_santo_amaro {
        int hora_do_dia <- cycle % 24;
        point destino;
        
        // Comportamento típico: 6h-8h ida trabalho, 17h-19h volta
        if (hora_do_dia >= 6 and hora_do_dia < 9) {
            destino <- localizacao_trabalho;
            em_casa <- false;
        } else if (hora_do_dia >= 17 and hora_do_dia < 20) {
            destino <- localizacao_casa;
            em_casa <- true;
        } else if (hora_do_dia >= 9 and hora_do_dia < 17) {
            // Horário comercial - movimento local
            do wander amplitude: 200.0;
            return;
        } else {
            // Noite - em casa
            do wander amplitude: 50.0;
            return;
        }
        
        if (distance_to(destino) > 10.0) {
            float velocidade <- usa_transporte_publico ? 2.5 : 1.0;
            do goto target: destino speed: velocidade;
        }
    }
    
    // === ASPECTO VISUAL ===
    aspect base {
        draw circle(4) color: 
            infectado ? #red :
            recuperado ? #green :
            imune ? #blue : #gray;
    }
}

// === ESPÉCIE MOSQUITOS - AEDES SANTO AMARO ===
species mosquitos skills: [moving] {
    // Estado do vetor
    bool infectivo <- false;
    int dias_vida <- 0;
    int dias_infeccao <- 0;
    bool incubando <- false;
    
    // Comportamento adaptado a Santo Amaro
    point criadouro <- location;
    float taxa_alimentacao <- rnd(0.2, 0.4); // Mais agressivo em área urbana
    int ciclo_alimentacao <- rnd(2, 3);      // Alimenta-se mais frequentemente
    
    // === COMPORTAMENTOS ===
    reflex atualizar_estado {
        dias_vida <- dias_vida + 1;
        
        // Mortalidade: maior em áreas urbanas com controle
        float prob_morte <- min(0.9, dias_vida / 25.0);
        prob_morte <- prob_morte + 0.1; // +10% mortalidade em área urbana
        
        if (flip(prob_morte)) {
            die();
            return;
        }
        
        // Incubação mais rápida em clima quente de Santo Amaro
        if (incubando) {
            dias_infeccao <- dias_infeccao + 1;
            if (dias_infeccao >= global.tempo_incubacao_mosquito) {
                infectivo <- true;
                incubando <- false;
            }
        }
    }
    
    reflex picar {
        if (cycle % ciclo_alimentacao != 0) return;
        
        humanos alvo <- one_of(humanos at_distance 20.0); // Maior alcance
        
        if (alvo != nil and not alvo.recuperado) {
            // Mosquito → Humano
            if (infectivo and not alvo.infectado and not alvo.imune) {
                if (flip(global.prob_transmissao_mos_hum * alvo.suscetibilidade)) {
                    alvo.infectado <- true;
                    alvo.dias_infeccao <- 1;
                    alvo.area_residencia.casos_reportados <- alvo.area_residencia.casos_reportados + 1;
                }
            }
            
            // Humano → Mosquito
            if (alvo.infectado and not infectivo and not incubando) {
                if (flip(global.prob_transmissao_hum_mos)) {
                    incubando <- true;
                    dias_infeccao <- 0;
                }
            }
        }
    }
    
    reflex reproducao_santo_amaro {
        // Condições ideais em Santo Amaro: clima quente e úmido
        bool condicoes_ideais <- global.temperatura_externa between [24.0, 32.0] 
                              and global.umidade > 65.0 
                              and global.precipitacao > 3.0;
        
        // Reprodução mais frequente em áreas de alto risco
        area_risco area_atual <- one_of(area_risco covering (location));
        float bonus_reproducao <- (area_atual != nil and area_atual.nivel_risco >= 4) ? 0.1 : 0.0;
        
        if (condicoes_ideais and flip(0.08 + bonus_reproducao)) {
            create mosquitos number: rnd(1, 3) {
                location <- myself.location + {rnd(-25.0, 25.0), rnd(-25.0, 25.0)};
                criadouro <- myself.criadouro;
            };
        }
    }
    
    reflex mover_mosquito {
        point alvo <- nil;
        
        // Prefere áreas com humanos
        if (flip(0.8)) { // 80% chance de procurar humano
            humanos humano_proximo <- one_of(humanos at_distance 150.0);
            if (humano_proximo != nil) {
                alvo <- humano_proximo.location;
            }
        }
        
        if (alvo = nil) {
            // Volta para criadouro ou área próxima
            alvo <- criadouro + {rnd(-30.0, 30.0), rnd(-30.0, 30.0)};
        }
        
        do goto target: alvo speed: 0.4 + rnd(0.3);
    }
    
    // === ASPECTO VISUAL ===
    aspect base {
        draw circle(3) color: 
            infectivo ? #orange :
            incubando ? #yellow : #brown;
    }
}

// === EXPERIMENTO SANTO AMARO ===
experiment santo_amaro_simulacao type: gui {
    // === PARÂMETROS ESPECÍFICOS SANTO AMARO ===
    parameter "População Residentes" var: pop_humanos category: "Demografia" 
        min: 50 max: 500 default: 100;
    
    parameter "População Mosquitos" var: pop_mosquitos category: "Entomologia" 
        min: 50 max: 300 default: 100;
    
    parameter "Temp. Média Santo Amaro" var: temperatura_externa category: "Clima" 
        min: 20.0 max: 32.0 default: 26.8;
    
    parameter "Índice Chuva" var: precipitacao category: "Clima" 
        min: 0.0 max: 40.0 default: 8.5;
    
    parameter "Transmissão M→H" var: prob_transmissao_mos_hum category: "Epidemiologia" 
        min: 0.2 max: 0.7 default: 0.45;

    output {
        display mapa_santo_amaro {
            background #white;
            camera: santo_amaro_boundary;
            
            // Título
            graphics "titulo" {
                draw "📍 SANTO AMARO - SÃO PAULO/SP" at: {0.1, 0.95} color: #darkblue size: 15;
                draw "Simulação de Disseminação da Dengue" at: {0.1, 0.92} color: #darkred size: 12;
            }
            
            // Áreas de risco
            species area_risco aspect: visual;
            
            // Criadouros
            graphics "criadouros" {
                loop ponto over: criadouros_potenciais {
                    draw triangle(6) at: ponto color: #cyan border: #darkblue;
                }
            }
            
            // Humanos
            species humanos aspect: base;
            
            // Mosquitos
            species mosquitos aspect: base;
            
            // Legenda
            graphics "legenda" {
                draw rectangle(200, 120) at: {0.02, 0.02} color: #white border: #black opacity: 0.8;
                draw "LEGENDA SANTO AMARO:" at: {0.03, 0.15} color: #black size: 10;
                draw "● Residentes" at: {0.03, 0.25} color: #gray size: 9;
                draw "● Infectados" at: {0.03, 0.35} color: #red size: 9;
                draw "● Mosquitos" at: {0.03, 0.45} color: #brown size: 9;
                draw "▲ Criadouros" at: {0.03, 0.55} color: #cyan size: 9;
                draw "Áreas Risco 4-5" at: {0.03, 0.65} color: #orange size: 9;
            }
        }
        
        display dashboard_santo_amaro {
            layout: vertical;
            
            chart curva_epidemiologica type: series title: "Curva Epidemiológica - Santo Amaro" {
                data "Infectados" value: total_infectados_h color: #red;
                data "Recuperados" value: total_recuperados color: #green;
                data "Suscetíveis" value: count(humanos where (not each.infectado and not each.recuperado)) color: #blue;
            }
            
            chart risco_areas type: series title: "Casos por Área de Risco" {
                loop area over: area_risco {
                    data area.nome value: area.casos_reportados color: 
                        area.nivel_risco = 5 ? #red :
                        area.nivel_risco = 4 ? #orange :
                        area.nivel_risco = 3 ? #yellow : #green;
                }
            }
            
            monitor "📍 Localização" value: "Santo Amaro, Zona Sul SP";
            monitor "👥 Residentes Ativos" value: count(humanos);
            monitor "🦟 População Mosquitos" value: count(mosquitos);
            monitor "🤒 Casos Ativos" value: total_infectados_h;
            monitor "📈 R₀ Instantâneo" value: r0_instantaneo;
            monitor "🌡️ Temperatura" value: temperatura_externa + "°C";
            monitor "💧 Precipitação" value: precipitacao + " mm";
            monitor "🔥 Áreas Alto Risco" value: count(area_risco where (each.nivel_risco >= 4)) + "/4";
        }
    }
}