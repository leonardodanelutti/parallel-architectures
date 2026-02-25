#import "lib.typ": *
#import "@preview/lovelace:0.3.0": *

#set text( lang: "it" )

#show: ams-article.with(
  paper-size: "a4",
  title: [Progetto per il corso di Architetture Parallele - minimizzazione di fix-set per 2-SAT],
  abstract: [
  Il progetto affronta la risoluzione di istanze 2-SAT con l'obiettivo di identificare un insieme minimo di variabili (fix-set) che, una volta assegnate, rendono la formula soddisfacibile con una sola soluzione. L'obbiettivo è quello di implementare un euristica per approssimare il risultato su istanze di grandi dimensioni, sfruttando la potenza di calcolo parallelo delle GPU.
  ],
  authors: (
    (
      name: "Leonardo Danelutti",
      organization: [Università di Udine],
      email: "danelutti.leonardo@spes.uniud.it",
    ),
  ),
  supervisors: (),
  bibliography: bibliography("refs.bib"),
)

= Descrizione del problema

Data un istanza di formule booleane in forma normale congiuntiva con clausole di al massimo due letterali, si cerca un insieme di variabili, e un relativo assegnamento di verità, tale che la formula ammetta un unica soluzione soddisfacibile.

#definition[
Data una formula booleana $P$ in forma normale congiuntiva (CNF) con clausole di al massimo due letterali (2-CNF), si cerca un sottoinsieme delle variabili in $P$, che chiameremo fix-seto $X$, e un relativo assegnamento di verità $f$ tale che la formula $P[x |-> f(x)]_(x in X)$, ovvero la formula ottenuta da $P$ sostituendo ogni variabile $x$ in $X$ con il suo valore assegnato da $f$, sia soddisfacibile e ammetta un'unica soluzione.
]

Ad esempio, un fix-set banale per una formula soddisfacibile è l'insieme di tutte le variabili, il problema più interessante è trovare un fix-set di dimensione minima.

== Richiami teorici
Un'istanza 2-SAT può essere rappresentata tramite un *grafo delle implicazioni* $G = (V, E)$, dove i nodi $V$ rappresentano i letterali (variabili e loro negazioni) e gli archi $E$ rappresentano le implicazioni logiche derivanti dalle clausole. Una clausola $(a or b)$ genera gli archi $(not a => b)$ e $(not b => a)$.

E' facile vedere che un'istanza è soddisfacibile se e solo se, per ogni variabile $x$, i letterali $x$ e $not x$ non possono raggiungersi reciprocamente nel grafo delle implicazioni. In altre parole, $x$ e $not x$ devono appartenere a componenti fortemente connesse (SCC) distinte. Se $x$ e $not x$ sono nella stessa SCC, allora la formula è insoddisfacibile. 

Inoltre, presa un istanza soddisfacibile, ogni letterale che si trova in una stessa SCC deve essere assegnato lo stesso valore di verità in ogni soluzione soddisfacibile. Si può quindi costruire un DAG (Directed Acyclic Graph) delle SCC, dove ogni nodo rappresenta una SCC e gli archi rappresentano le implicazioni tra di esse. Possiamo quindi ragionare su questo grafo condensato, per ogni nodo poi sara necessario prendere un unico letterale rappresentante della SCC.

Alcune variabili, che chiameremo *backbone*, devono necessariamente assumere un certo valore in ogni soluzione soddisfacibile. Queste variabili possono essere identificate analizzando il grafo condensato. 

#theorem[
Sia $P$ un'istanza soddisfacibile di 2-SAT, e sia $G$ il suo grafo delle implicazioni. Esiste un nodo $v$ in $G$ tale che $v$ raggiunge $not v$ se e solo se $v$ è falsa in ogni soluzione soddisfacibile, e quindi fa parte del backbone. Analogamente, $not v$ raggiunge $v$ se e solo se $v$ è vera in ogni soluzione soddisfacibile, e quindi fa parte del backbone.
]

#proof[

  $=>)$Supponiamo che $v$ raggiunga $not v$, cioè che esiste una catena di implicazioni $v -> l_1 -> ... -> l_n ->not v$. Se assegnamo vero a $v$ allora per le implicazioni $l_1, ..., l_n$ devono essere assegnati a vero, e quindi $not v$ deve essere assegnato a vero, ma questo è una contraddizione.

  $arrow.double.l$) Supponiamo che $v$ sia falsa in ogni soluzione soddisfacibile, e supponiamo per assurdo che $v$ non raggiunga $not v$.
  - Se $not v$ raggiunge $v$, allora $not v$ è falsa in ogni soluzione soddisfacibile, e quindi $v$ è vera in ogni soluzione soddisfacibile, ma questo è una contraddizione.
  - Se $not v$ non raggiunge $v$, allora nessun altro letterale $l$ raggiungibile da $v$ può raggiungere il suo complementare, se cosi fosse avremmo una catena di implicazioni $v ->^* l ->^* not l ->^* not v$. Quindi possiamo assegnare vero a $v$ e questo non porta a contraddizioni, ma questo è una contraddizione con l'ipotesi che $v$ è falsa in ogni soluzione soddisfacibile.

  Lo stesso vale per il caso duale in cui $not v$ raggiunge $v$.
]

Tutti le variabili del backbone hanno lo stesso valore in ogni soluzione soddisfacibile, quindi non serve includerle nel fix-set, è sufficiente assegnarle e rimuoverle dal problema semplificandolo.

Un altra affermazione importante è che se un node viene assegnato il valore di verità vero, allora tutti i nodi che raggiunge devono essere assegnati a vero, e in modo duale se un nodo viene assegnato a falso, allora tutti i nodi che lo raggiungono devono essere assegnati a falso. In generale quindi è preferibile aggiungere al fix-set nodi sorgente o pozzo nel DAG condensato, in modo che l'aggiunta del nodo porti a propagare (e quindi eliminare) i valori di verità a più nodi possibili.

= Algoritmo Overview
La soluzione implementata segue una pipeline di elaborazione del grafo delle implicazioni, che si articola in più fasi:

+ *Calcolo delle SCC*: Identificazione delle componenti fortemente connesse.
+ *Ordinamento Topologico*: Calcolo dei livelli topologici del DAG delle SCC per facilitare l'analisi della raggiungibilità.
+ *Calcolo del Backbone*: Identificazione del backbone, per rimuovere le variabili che assumono lo stesso valore in tutte le soluzioni.
Il calcolo del backbone, come anticipato, consiste di verificare se un letterale può raggiungere il suo complementare nel DAG condensato. Dato che dobbiamo calcolare la raggiungibilità tra coppie di nodi in un DAG, è possibile farlo partendo dai nodi sorgente e propagando la raggiungibilità fino a raggiungere i nodi pozzo. Di seguito lo pseudocodice dell'algoritmo per il calcolo del backbone.

#figure(
  kind: "algorithm",
  supplement: [Algoritmo],
  pseudocode-list(booktabs: true, stroke:none, numbered-title: [Backbone])[
    *Input:* Un DAG $G=(V, E)$ con $n = |V|$ e l'ordinamento topologico di $G$ \
    *Output:* Una lista di variabili che fanno parte del backbone
    + Inizializza un array *reachability* di dimensione $n times n$, con *false*
    + Inizializza una lista vuota *backbone*
    + *for each* nodo $u$ in $G$ in ordine topologico *do* \
      + reachability[u][u] = true \

      + *if* reachability[u][complementare(u)] *then* \
        + $u$ è sempre vero, complementare($u$) è sempre falso\
        + Aggiungi $u$ e complementare($u$) alla lista *backbone* \
        
      
      + *for each* $(u, v) in E$ *do* \
        + reachability[v] = reachability[v] OR reachability[u]

  ]
) <backbone>


+ *Calcolo delle WCC*: Suddivisione del grafo rimanente in componenti debolmente connesse (Weakly Connected Components o WCC), che possono essere risolte indipendentemente.
+ *Ricerca Euristica*: Applicazione di tecniche iterative per selezionare variabili da aggiungere al fix-set $X$.
Ad ogni iterazione, viene selezionata una variabile da aggiungere al fix-set, e il grafo viene semplificato propagando le assegnazioni di verità. Il processo continua fino a quando tutte le variabili sono state assegnate, ovvero fino a quando il grafo è completamente semplificato. E' importante notare che dato che tutte le variabili del backbone sono state rimosse, questo processo non può portare a contraddizioni, cioè non può portare a situazioni in cui l'assegnazione di un letterale contraddice l'assegnazione del suo complementare.

Possiamo operare su ogni WCC in modo indipendente, ci posso essere due casi:
+ Un letterale $x$ e il suo complementare $not x$ si trovano nella stessa WCC, in questo caso ciò vale per ogni letterale nella WCC. Prendiamo un letterale $y$ nella stessa WCC di $x$, si ha quindi che $x ->^* y$ oppure $y ->^* x$ ma deve quindi valere anche $not x ->^* not y$ oppure $not y ->^* not x$, in entrambi i casi $y$ e $not y$ si trovano nella stessa WCC.
+ Un letterale $x$ e il suo complementare $not x$ si trovano in WCC distinte, in questo caso ogni letterale nella WCC di $x$ non raggiunge il suo complementare per un motivo simile a quello visto sopra.
Per ogni iterazione se la WCC è del caso 1. possiamo scegliere un qualsiasi letterale nella WCC da aggiungere al fix-set, se invece è del caso 2. possiamo scegliere solo un letterale tra le due coppie di WCC.
Ci riferiremo a "WCC complementare" per indicare lo stesso WCC nel caso 1, e per indicare la WCC che contiene i complementari dei letterali nel caso 2.

#figure(
  kind: "algorithm",
  supplement: [Algoritmo],
  pseudocode-list(booktabs: true, stroke:none, numbered-title: [Backbone])[
    + *while* esistono nodi non assegnati *do* \
      + *for each* coppia di WCC complementari $C$ *do* \
        + Applica l'euristica per selezionare un nodo candidato $u$ da $C$ \
        + Aggiungi il nodo selezionato al fix-set $X$
        + Propaga le assegnazioni di verità a tutti i nodi raggiunti da $u$, e a tutti i nodi che raggiungono il complementare di $u$ \
        + Rimuovi i nodi assegnati e aggiorna le WCC

  ]
) <backbone>

= Euristiche
Sono state implementate diverse euristiche per guidare la selezione delle variabili da aggiungere al fix-set, queste ad ogni iterazione vengono applicate come specificato sopra.

+ *Heuristic 1*: Seleziona un nodo sorgente, ad ogni iterazione le sorgenti vengono ricalcolate
+ *Heuristic 2*: Seleziona il nodo con più alto out-degree, ad ogni iterazione viene ricalcolato l'out-degree
+ *Heuristic 3*: Seleziona il nodo con la più alta raggiungibilità, ovvero il nodo che raggiunge più altri nodi nel DAG condensato. Ad ogni iterazione non viene ricalcolata la raggiungibilità, viene solo aggiornata per i nodi rimossi a 0.
+ *Heuristic 4*: Variante della Heuristic 3 che prevede il ricalcolo dinamico della raggiungibilità dopo ogni assegnamento, per una precisione maggiore a scapito del tempo di calcolo.

E' importante notare come il complementare di nodo sorgente in un WCC è un nodo pozzo nel WCC complementare, e questo vale in modo analogo con tutte le metriche che utilizzano le euristiche, ad esempio se un nodo ha out-degree d, allora il suo complementare ha in-degree d, se un nodo raggiunge n altri nodi, allora il suo complementare è raggiunto da n nodi. Quindi in realtà, in ogni euristica, non controlliamo solo in "avanti" ma anche "indietro", e questo è importante per guidare la selezione delle variabili in modo più efficace.

= Esempio

Nella @ex1 viene mostrato un esempio di un possibile grafo delle implicazioni, nodi bianchi rappresentano i letterali non negati mentre nodi rossi rappresentano i letterali negati, gli archi rappresentano le implicazioni logiche. Il primo passo è quello di calcolare le componenti fortemente connesse, in questo caso abbiamo 4 SCC, rappresentate dalle zone colorate in azzurro. La variabile $x_7$ fa parte del backbone, in quanto raggiunge il suo complementare $not x_7$. Dopo l'eliminazione del backbone, il grafo rimanente è costituito da 2 WCC, rappresentate dai riquadri bianchi sullo sfondo.

#figure(
  image("es1.png", height: 50%),
  caption: [Esempio di grafo delle implicazioni],
)<ex1>

Dopo l'eliminazione dei backbone ci ritroviamo nella situazione descritta nella prima immagine di @ex1_h4, dove abbiamo evidenziato le WCC rimanenti. Quindi immaginiamo di applicare l'euristica 4, che prevede il ricalcolo dinamico della raggiungibilità dopo ogni assegnamento. Nella prima iterazione, i letterali $x_3, x_8, not x_6 , x_5$ sono tutti dei candidati per essere aggiunti al fix-set e quindi poi essere eliminati dato che raggiungono tutti due nodi. Supponiamo di scegliere $x_8$, dopo averlo assegnato a vero, e quindi eliminato, si propagano le assegnazioni di verità. Questo viene fatto anche nella WCC complementare, quindi $not x_8$ viene assegnato a falso e eliminato, e si propagano le assegnazioni di verità anche per i nodi che raggiungono $not x_8$. Dopo questa iterazione, la situazione è quella mostrata nella terza immagine di @ex1_h4, ora l'unico nodo candidato è $not x_6$, l'unico che raggiunge due nodi, quindi lo aggiungiamo al fix-set. Dopo averlo assegnato a vero e propagato le assegnazioni di verità abbiamo terminato in quanto non ci sono più nodi da assegnare. Il fix-set trovato è $X = {x_8, x_6}$, con assegnamenti $f(x_8) = "true", f(x_6) = "false"$.

#figure(
  image("es1_h4.png", width: 100%),
  caption: [Applicazione dell'euristica 4 sull'esempio precedente],
)<ex1_h4>

In caso di più coppie di WCC complementari possiamo scegliere un nodo per ogni coppia.

= Implementazione // TODO:
L'implementazione sfrutta **CUDA** per massimizzare il throughput del calcolo su grafi.

== Rappresentazione dei dati
Il grafo è memorizzato in formato **Compressed Sparse Row (CSR)**, che permette un accesso efficiente alla memoria globale della GPU durante l'attraversamento degli archi.

== Euristiche implementate

L'implementazione della raggiungibilità via bitset utilizza una tecnica di **chunking** della memoria per gestire grafi con milioni di nodi senza esaurire la VRAM della GPU.

= Risultati sperimentali //TODO:

== Architettura utilizzata
#figure(
  table(
    columns: 3,
    [Device Name], [Nvidia Tesla T4], [Intel Xeon E5 v3],
    [Mirco-Architecture], [Turing], [Haswell],
    [SMs / Sockets], [40], [1],
    [Cores], [2560 CUDA cores], [2 cores with 2 threads each], 
    [Boost Frequency], [1.59 GHz], [3.6 GHz],
    [Peak FLOPS (FP32)], [8.1 TFLOPS], [147 GFLOPS],
    [Memory], [16 GB GDDR6], [15GB DDR4],
    [Cache], [6 MiB (L2 Cache)], [45 MiB (L3 Cache)]
  )
)

== Metodo di generazione dei dati



== Analisi delle performance
Le analisi condotte mostrano che:
- Il calcolo delle SCC e del Backbone scala linearmente con la dimensione del grafo.
- Le euristiche 3 e 4, sebbene più costose computazionalmente, producono fix-set significativamente più piccoli rispetto alle euristiche semplici (1 e 2).
- Il chunking della memoria bitset permette di processare istanze che richiederebbero altrimenti decine di gigabyte di memoria.

= Valutazioni e osservazioni
I risultati ottenuti confermano l'efficacia dell'approccio parallelo. La GPU permette di analizzare la struttura del grafo delle implicazioni con una velocità ordini di grandezza superiore rispetto ad un approccio seriale, specialmente nella fase di calcolo della raggiungibilità.


== Mini-guida all'uso
Compilazione:
```bash
make
```
Dopo aver compilato, si otterrà un eseguibile chiamato `fix`, che può essere utilizzato per risolvere istanze di 2-SAT e trovare un fix-set approssimato.

Esecuzione:
```bash
./fix <percorso_istanza.cnf> [heuristic list] [--check-sodd] [--bench] [--bench-file <path>]
```
- `<percorso_istanza.cnf>`: Il percorso al file contenente l'istanza di 2-SAT in formato CNF.
- `[heuristic list]`: Una lista opzionale di euristiche da applicare, ad esempio `--heuristics 1,3` per applicare le euristiche 1 e 3. Se non viene specificata alcuna euristica, verranno applicate tutte le euristiche disponibili.
- `--check-sodd`: Opzione per verificare se l'istanza è soddisfacibile
- `--bench`: Opzione per abilitare il benchmarking delle prestazioni.
- `--bench-file <path>`: Specifica un file di output per i risultati del benchmark, se non specificato i risultati del benchmark verranno salvati su `benchmarks.csv`.

Sono stati utilizzati anche due script python per generare istanze di 2-SAT e per eseguire i benchmark su più istanze in modo automatico. Questi script si trovano nella cartella `scripts/`.

Per la generazione di istanze soddisfacibili:

```bash
python scripts/generate_instances.py <num_var_start> <num_var_end> <num_var> <ratio_start> <ratio_end> <num_ratio> <output_dir> [--clingo-timeout <seconds>]
```

- `<num_var_start>`: Numero minimo di variabili per le istanze generate.
- `<num_var_end>`: Numero massimo di variabili per le istanze generate.
- `<num_var>`: Numero di istanze, rispetto al numero di variabili, da generare.
- `<ratio_start>`: Rapporto minimo tra clausole e variabili per le istanze generate.
- `<ratio_end>`: Rapporto massimo tra clausole e variabili per le istanze generate.
- `<num_ratio>`: Numero di istanze, rispetto al rapporto clausole/variabili, da generare.
- `<output_dir>`: Directory di output dove salvare le istanze generate.
- `--clingo-timeout <seconds>`: Timeout in secondi per la risoluzione dell'istanza tramite Clingo, se non specificato, clingo non viene eseguito.

All'interno del file inoltre si possono cambiare SEED ed il metodo per generare il numero delle istanze.

Per eseguire i benchmark su più istanze:
```bash
python scripts/run_benchmark.py <instances dir>  <heuristic list>  <out file> [--check-sodd]
```
- `<instances dir>`: Directory contenente le istanze da testare.
- `<heuristic list>`: Una lista di euristiche da applicare, ad esempio `--heuristics 1,3` per applicare le euristiche 1 e 3.
- `<out file>`: File di output per i risultati del benchmark, ad esempio `benchmark_results.csv`.
- `--check-sodd`: Opzione per verificare se le istanze sono soddisfacibili prima di eseguire il benchmark.


== Riproducibilità
Per rieseguire i benchmark completi si possono utilizzare i comandi commentati nella funzione "main" degli script di generazione dei dati e di benchmarking.
