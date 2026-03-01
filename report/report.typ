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

= Algoritmo Overview <alg-overview>
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
      + *end for*
    + *end for*
  ]
) <backbone>


+ *Calcolo delle WCC*: Suddivisione del grafo rimanente in componenti debolmente connesse (Weakly Connected Components o WCC), che possono essere risolte indipendentemente.
+ *Ricerca Euristica*: L'algoritmo procede iterativamente finché tutti i nodi non sono stati assegnati. Ad ogni iterazione, viene selezionata una variabile da aggiungere al fix-set, e il grafo viene semplificato propagando le assegnazioni di verità. Il processo continua fino alla completa semplificazione del grafo. È importante notare che, essendo le variabili del backbone già state rimosse, questo processo non presenta contraddizioni logiche: non possono verificarsi situazioni in cui l'assegnazione di un letterale entri in conflitto con l'assegnazione del suo complementare.

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
      + *end for*
    + *end while*
  ]
) <backbone>

= Euristiche
Sono state implementate diverse euristiche per guidare la selezione delle variabili da aggiungere al fix-set, queste ad ogni iterazione vengono applicate come specificato sopra.

+ *Heuristic 1*: Seleziona un nodo sorgente. Ad ogni iterazione, lo stato di nodo sorgente viene ricalcolato analizzando gli archi uscenti verso nodi non assegnati
+ *Heuristic 2*: Seleziona il nodo con il più alto out-degree. Ad ogni iterazione, il conteggio degli archi uscenti viene dinamicamente aggiornato escludendo i vicini già assegnati
+ *Heuristic 3*:Seleziona il nodo con la più alta raggiungibilità, ovvero il nodo che raggiunge il maggior numero di vertici nel DAG condensato. In questa variante, il calcolo della raggiungibilità viene effettuato una sola volta all'avvio, e iterativamente viene applicata una maschera per escludere i nodi rimossi
+ *Heuristic 4*: Variante della Heuristic 3 che prevede il ricalcolo totale e dinamico della raggiungibilità dopo ogni round di assegnamento, offrendo maggiore precisione a fronte di un costo computazionale più elevato

E' importante notare come il complementare di nodo sorgente in un WCC è un nodo pozzo nel WCC complementare, e questo vale in modo analogo con tutte le metriche che utilizzano le euristiche, ad esempio se un nodo ha out-degree $d$, allora il suo complementare ha in-degree $d$, se un nodo raggiunge $n$ altri nodi, allora il suo complementare è raggiunto da $n$ nodi. Quindi in realtà, in ogni euristica, non controlliamo solo "in avanti" ma anche "all'indietro", e questo è importante per guidare la selezione delle variabili in modo più efficace.


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

= Implementazione
In questa sezione vengono descritte le scelte implementative più rilevanti, per maggiori dettagli si rimanda al codice sorgente.

== Rappresentazione dei dati
L'input viene letto da file in formato DIMACS CNF, da questo viene costruito il grafo delle implicazioni dove al letterale $x$ corrisponde il nodo $2x$ e al letterale $not x$ corrisponde il nodo $2x + 1$. Il grafo viene rappresentato nel formato CSR (Compressed Sparse Row), che è una rappresentazione compatta ed efficiente per grafi sparsi, e permette di accedere rapidamente ai nodi adiacenti. Inoltra Il formato CSR garantisce l'accesso coalescente alla memoria globale della GPU, poiché la memorizzazione contigua degli archi adiacenti permette ai thread CUDA di massimizzare il throughput in lettura. L'aspetto meno svantaggioso del formato CSR è che non permette di accedere rapidamente ai nodi che raggiungono un nodo, ma questo non sarà necessario nel nostro caso.

== Calcolo delle SCC
Per il calcolo delle SCC è stato implementato l'algoritmo proposto in @SCC-algorithm, che viene riportato in @SCC-algorithm-pseudocode. L'algoritmo assegna ad ogni nodo $v$ due valori, $v_"in"$ e $v_"out"$, alla fine della computazione i valori $v_"in"$ e $v_"out"$ saranno uguali e rappresenteranno l'identificatore della SCC a cui $v$ appartiene.

L'algoritmo consiste in un ciclo esterno (Linee 2-21) che itera fino a quando la computazione è convergente. Ogni iterazione si articola in tre fasi: inizializzazione, propagazione dei valori massimi e rimozione degli archi.

La prima fase (Linee 3-6) inizializza i due valori di ciascun vertice all'ID del vertice corrispondente.

La seconda fase (Linee 7-14) propaga i valori massimi lungo gli archi. Per ogni arco diretto, il valore "out" del vertice sorgente viene aggiornato al valore "out" del vertice destinazione se quest'ultimo è maggiore. Analogamente, il valore "in" del vertice destinazione viene aggiornato al valore "in" del vertice sorgente se quest'ultimo è maggiore. Questa fase si ripete fino a raggiungere un punto fisso, ovvero finché nessun valore "in" o "out" cambia più.

La terza fase (Linee 15-19) rimuove gli archi i cui vertici sorgente e destinazione appartengono a SCC diverse. Rilevare questa condizione è semplice: se i valori del sorgente e della destinazione differiscono, i due vertici non appartengono alla stessa SCC e l'arco può essere rimosso. Le tre fasi si ripetono sul grafo ridotto, che ha gli stessi vertici ma meno archi.

L'algoritmo termina quando tutti i vertici hanno una firma in cui il valore "in" coincide con il valore "out".

#figure(
  kind: "algorithm",
  supplement: [Algoritmo],
  pseudocode-list(booktabs: true, stroke:none, numbered-title: [ECL-SCC])[
    *Input:* Directed graph $G = (V, E)$ with unique vertex IDs

    *Output:* $forall v : v_"in"$ denotes to which SCC vertex $v$ belongs

    + $"converged" = "false"$
    + *while* not $"converged"$ *do*
      + *for all* vertices $v in V$ *do*
        + $v_"in" = v_"id"$
        + $v_"out" = v_"id"$
      + *end for*
      + $"updated" = "true"$
      + *while* $"updated"$ *do*
        + *for all* edges $(u, v) in E$ *do*
          + $v_"out" = max(v_"out", u_"out")$
          + $v_"in" = max(v_"in", u_"in")$
        + *end for*
        + $"updated" =$ at least one $v_"in"$ or $v_"out"$ value changed
      + *end while*
      + *for all* edges $(u, v) in E$ *do*
        + *if* $u_"in" != v_"in"$ or $u_"out" != v_"out"$ *then*
          + $E = E without (u, v)$
        + *end if*
      + *end for*
      + $"converged" =$ all $v_"in" == v_"out"$
    + *end while*
  ]
) <SCC-algorithm-pseudocode>

Alla fine dell'algoritmo, l'identificatore della SCC corrisponde al nodo con ID più alto in quella SCC.

Ogni fase dipende dal risultato della fase precedente quindi non è possibile parallelizzare. La fase 1 è facilmente parallelizzabile e non richiede sincronizzazione, mentre la fase 3 richiede un `atomicAdd` per la costruzione della nuova lista di archi. La fase 2 è quella che richiede più tempo e può essere implementata con due operazioni atomiche ma gli autori hanno utilizzato un approccio che non utilizza operazioni atomiche, ma richiede più iterazioni per convergere, in questo modo ogni iterazione è completamente parallela e non c'è contesa tra i thread.

Dopo il calcolo delle SCC, è possibile costruire il grafo condensato, che è un DAG in cui ogni nodo rappresenta una SCC, e gli archi rappresentano le implicazioni tra le SCC. Per fare ciò gli ID delle componenti connesse vengono riassegnati nell'intervallo $[0, "#SCC")$, viene poi costruita una nuova lista di archi in cui ogni arco $(u, v)$ del grafo originale viene trasformato in un arco $("scc_id"[u], "scc_id"[v])$ se $"scc_id"[u] != "scc_id"[v]$. Da questa lista viene poi costruito il grafo condensato in formato CSR utilizzando alcune funzioni della libreria `thrust`.

La proprietà che l'ID di ogni SCC è dato dal nodo con ID più alto in quella SCC semplifica molto i conti. Infatti se la variabile con ID più alto in una SCC è $u$, e quindi l'SCC ha ID $2u$, allora l'SCC complementare che contiene $not u$ ha ID $2u + 1$, e lo stesso vale se la variabile con ID più alto in una SCC è $not u$, e quindi l'SCC ha ID $2u + 1$, allora l'SCC complementare che contiene $u$ ha ID $2u$. Le SCC complementari si trovano quindi in posizioni adiacenti, come avveniva per i letterali, e sono sempre una pari e l'altra dispari.

Per trovare il complementare di una SCC con ID $i$ sara quindi sufficiente fare $i "XOR" 1$, dove XOR è l'operazione bitwise XOR.

== Calcolo dell'ordinamento topologico

Per l'ordinamento topologico è stata implementata una versione parallela dell'algoritmo di Kahn. La procedura si sviluppa iterativamente processando una "frontiera" di nodi con grado di ingresso nullo e rimuovendoli virtualmente dal grafo, aggiornando di conseguenza i gradi dei nodi adiacenti fino all'esaurimento dei vertici.

Un'ottimizzazione cruciale in questa fase iniziale riguarda la costruzione e l'utilizzo dell'array dei gradi di ingresso (in-degree). In questo contesto, l'array funge da contatore delle dipendenze per ciascun vertice: un nodo è considerato "sbloccato" e pronto per essere inserito nella successiva frontiera di elaborazione solo quando il suo contatore scende a zero, indicando che tutti i suoi predecessori nel DAG sono già stati visitati. Sfruttando le proprietà di simmetria del problema, è stato possibile evitare un'esplorazione atomica globale per l'inizializzazione di questi contatori: analizzando la rappresentazione CSR, il numero di archi uscenti da un generico nodo u — calcolabile in tempo costante come row_ptr[u+1] - row_ptr[u] — corrisponde esattamente al numero di archi entranti del suo nodo complementare. 

Durante l'attraversamento, l'algoritmo procede rigorosamente per livelli topologici. Ad ogni iterazione, i thread elaborano in parallelo la frontiera corrente visitando i nodi adiacenti e decrementandone attivamente i contatori delle dipendenze. Per garantire la correttezza sia il decremento dei gradi sia l'accodamento dei nuovi nodi che raggiungono un in-degree pari a zero vengono gestiti tramite le primitive atomiche.

== Calcolo del backbone

Per calcolare il backbone, come anticipato, è necessario verificare se un letterale può raggiungere il suo complementare nel DAG condensato. Per fare ciò, rispetto a quanto scritto nel @alg-overview, sono state implementate diverse accortezze. 

L'allocazione diretta di una matrice di raggiungibilità di dimensione $O(n^2)$ risulta impraticabile su GPU per grafi di grandi dimensioni a causa dei severi limiti della VRAM. Invece di allocare un valore booleano per ogni singola query, lo stato di raggiungibilità viene compresso utilizzando interi a 64 bit (`unsigned long long`). Questo approccio permette di mappare e valutare simultaneamente fino a 64 query di raggiungibilità, corrispondenti ad altrettante coppie di nodi. Di conseguenza, l'operazione logica di disgiunzione (OR) descritta nello pseudocodice si traduce in una singola istruzione hardware atomicOr, la quale incrementa drasticamente il throughput e riduce l'impronta di memoria di un fattore 64. 

Per prevenire errori di esaurimento della memoria su grafi di grandi dimensioni, le query vengono suddivise in batch da 64 elementi, i quali sono a loro volta raggruppati in chunk di dimensione calcolata dinamicamente per non eccedere un limite di VRAM prestabilito (ad esempio, 8 GB). L'host lancia iterativamente il kernel CUDA per ciascun chunk, garantendo la scalabilità dell'algoritmo indipendentemente dal numero totale di nodi. Grazie a questo design, un blocco di thread carica la lista di adiacenza di un nodo esattamente una volta per batch, ammortizzando il costoso prelievo in memoria globale su 64 esplorazioni simultanee e massimizzando così l'utilizzo della cache.

Infine, per garantire la correttezza della propagazione dei dati, l'elaborazione del grafo avviene rigorosamente livello per livello, basandosi sulle profondità estratte dall'ordinamento topologico. All'interno del kernel, i thread elaborano in parallelo i nodi appartenenti al medesimo livello e si sincronizzano esplicitamente (__syncthreads()) prima di procedere al livello successivo. Questa barriera previene l'insorgenza di race condition e assicura che, nel momento in cui un nodo propaga la propria maschera di raggiungibilità verso i figli, lo stato di tutti i suoi antenati sia già stato integralmente e definitivamente risolto in una singola passata.

Alla fine del processo viene ritornata una lista di assegnamenti `assignments`: per ogni nodo $u$, se $u$ raggiunge il suo complementare, allora `assignments[u] = 0` (falso) e `assignments[complementare(u)] = 1` (vero), altrimenti `assignments[u] = -1` (non assegnato).

== Calcolo delle WCC

Per il calcolo delle Weakly Connected Components (WCC) sul grafo residuo, è stato implementato un classico algoritmo parallelo basato su pointer jumping noto in letteratura come approccio Hook-and-Compress @WCC-algorithm. L'algoritmo opera in modo iterativo associando inizialmente ogni nodo a se stesso come radice. Successivamente, per ogni arco del grafo, la componente con l'identificativo maggiore viene annessa ("hooking") a quella con l'identificativo minore tramite operazioni atomiche, seguita da una fase di compressione dei cammini ("compress") per appiattire gli alberi risultanti. Per escludere i nodi eliminati nella fase precedente, il kernel esclude attivamente dall'elaborazione tutti i nodi nel backbone.

Una volta raggiunta la convergenza e finalizzato l'appiattimento degli alberi, è necessario raggruppare fisicamente i nodi appartenenti alla medesima componente per facilitare le elaborazioni successive. A tale scopo, è stata impiegata la libreria Thrust per ordinare i nodi in base all'ID della propria WCC e calcolarne le dimensioni tramite una riduzione (reduce_by_key). Il risultato finale viene infine riorganizzato e restituito utilizzando una struttura dati in formato CSR (Compressed Sparse Row), dove l'array row_ptr delimita l'inizio e la fine di ciascuna componente, mentre col_ind contiene gli identificativi dei nodi raggruppati, garantendo così accessi di memoria coalescenti nelle fasi a valle della pipeline.

== Calcolo delle euristiche

Il calcolo delle metriche per le euristiche 1 e 2 è relativamente semplice, in quanto si tratta di contare il numero di archi uscenti (out-degree) o di identificare i nodi sorgente, operazioni che possono essere eseguite in parallelo senza dipendenze tra i thread.

Per le euristiche basate sulla raggiungibilità (Heuristic 3 e 4), il conteggio per i nodi raggiungibili avviene propagando l'informazione nel ordine topologico inverso (dalle foglie verso le radici), dove i vertici aggregano parallelamente le maschere di bit dei propri figli. Al fine di rispettare i limiti della VRAM, anche questa fase operativa è strutturata a blocchi come per il caso del calcolo dei backbone. 

Una volta calcolati i punteggi, la selezione del candidato ottimale all'interno di ogni singola WCC è delegata alla libreria Thrust: tramite una riduzione parallela (reduce_by_key), l'algoritmo raggruppa i nodi per ID della componente ed estrae simultaneamente il vertice con il valore massimo. Successivamente, un altro kernel analizza le coppie di WCC complementari, decreta il vertice vincitore assoluto per ciascuna coppia e lo inserisce in una coda. Da qui prende avvio la fase di propagazione delle assegnazioni per ogni WCC, che segue il pattern della visita in ampiezza. I thread prelevano i nodi dalla coda e ne ispezionano i vicini: se un vertice adiacente risulta non ancora assegnato, il thread ne forza l'assegnamento (e lo stesso per il suo complementare) in modo sicuro e concorrente, avvalendosi della primitiva atomicCAS (Compare-And-Swap). I nodi modificati con successo vengono quindi accodati per la frontiera successiva, e il processo continua iterativamente fino a quando tutte le assegnazioni sono state propagate e non rimangono più nodi da processare.

= Risultati sperimentali

Per valutare le prestazioni dell'implementazione, sono state condotte una serie di analisi su istanze di 2-SAT. Viene utilizzata una macchina virtuale, con sistema operativo Debian 11, con le seguenti caratteristiche hardware:

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

== Metodo di generazione delle istanze <data-gen>

Per generare un istanza di 2-SAT con n variabili e m clausole, viene prima generato un assegnamento per le n variabili. Per ogni clausola da generare vengono scelti due letterali a caso, e viene controllato che almeno uno dei due letterali sia vero nell'assegnamento generato, in questo modo si garantisce che l'istanza sia soddisfacibile. Per ogni istanza è possibile quindi specificare sia il numero di variabili che il numero di clausole, si è quindi controllato come il grafo delle implicazioni cambia al variare del rapporto tra clausole e variabili, e come questo impatta sulle prestazioni dell'algoritmo. Al variare del rapporto e del numero di variabili, sono stati contati il numero di SCC e il numero di WCC. Si è subito notato che ogni conteggio aumenta linearmente con l'aumentare del numero di variabili, invece il rapporto clausole/variabili ha un impatto significativo.

Per visualizzare meglio questi risultati, è stata generata una griglia di istanze con numero di variabili che va da 100 a 5000, e rapporto clausole/variabili che va da 0.5 a 4.5. Le istanze variano 41 volte per quanto riguarda il numero di variabili, e 41 volte per quanto riguarda il rapporto clausole/variabili, per un totale di 1681 istanze. Per ogni istanza sono stati contati il numero di SCC e il numero di WCC dopo l'eliminazione dei backbone. 

Nella Figura 3 viene mostrato come il rapporto tra il numero di SCC e il numero di letterali varia rispetto al rapporto clausole/variabili. Per un rapporto $r<2$ (e quindi un rapporti archi/nodi nel grafo delle implicazioni $<1$) il numero di SCC è uguale al numero di letterali, mentre per $r>2$ inizia a diminuire. 

Per quanto riguarda il numero di WCC per SCC, mostrato nella Figura 4, si nota che per $r<2$ la funzione è decrescente, l'aggiunta di archi nel grafo delle implicazioni aggrega sempre più nodi e quindi sepre più componenti debolmente connesse. Per $r>2$ invece la funzione è crescente, questo per l'effetto dell'eliminazione dei backbone. Infatti, senza la loro eliminazione, il numero di WCC diminuirebbe fino a 1, dato che il grafo delle implicazioni diventerebbe sempre più connesso. L'eliminazione dei backbone diventa sempre più frequente all'aumentare del numero degli archi e quindi frammenta sempre di più il grafo, aumentando il numero di WCC.

#table(
  columns: 2,
  inset: 0pt,
  stroke: none,
  column-gutter: 15pt,
  figure(
    caption: [Il rapporto tra il numero di SCC e il numero di letterali al variare del rapporto clausole/variabili (Ratio)],
    image("../images/num_scc_per_lit_vs_ratio.png", width: 100%)
  ),
  figure(
    caption: [
      Il rapporto tra il numero di WCC e il numero di SCC al variare del rapporto clausole/variabili (Ratio)
    ],
    image("../images/num_wcc_per_scc_vs_ratio.png", width: 100%)
  ),
)

== Grado di approssimazione delle euristiche

Per valutare il grado di approssimazione delle euristiche, è stato confrontato il fix-set trovato da ogni euristica con un fix-set ottimale ottenuto tramite risoluzione esatta con Clingo, un solver ASP (Answer Set Programming) che permettere di scrivere i vincoli del problema in modo semplice e di ottenere soluzioni ottimali.

Sono state generate 41 istanze con rapporto clausole/variabili che va da 0.5 a 4.5 con 500 variabili per 10 volte. Per ogni istanza è stato calcolato il fix-set ottimale con Clingo, con un timeout di 400 secondi, e il fix-set approssimato con ogni euristica. Il tempo di esecuzione di Clingo sulle varie istanze può essere visualizzato nella @clingo_time, per rapporti tra 1.1 e 2.7 il tempo impiegato è notevolmente più alto.

#figure(
  caption: [Tempo di esecuzione di Clingo al variare del rapporto clausole/variabili, tempo in scala logaritmica],
  image("../images/boxplot_time_vs_ratio_res_ratio_500.png", width: 100%)
) <clingo_time>

Per ogni istanza è stato calcolato il rapporto tra la dimensione del fix-set approssimato e la dimensione del fix-set ottimale, e sono stati calcolati i valori medi di questo rapporto per ogni euristica al variare del rapporto clausole/variabili. I risultati sono mostrati nella @approx_all_heuristics_vs_ratio. 

L'euristica 1, che seleziona un nodo sorgente, è quella che si discosta maggiormente dall'ottimo. L'euristica 2 e 3 hanno un comportamento simile nelle regioni dove il problema è pù difficile, metre l'euristica 3 sembra avere il vantaggio altrimenti. L'euristica 4, che prevede il ricalcolo dinamico della raggiungibilità, è quella che si avvicina maggiormente all'ottimo, con un rapporto medio che si mantiene sempre inferiore a 1.25, e che si avvicina a 1 per rapporti tra clausole e variabili più alti.

#figure(
  caption: [Il rapporto tra la dimensione del fix-set approssimato e la dimensione del fix-set ottimale al variare del rapporto clausole/variabili, per ogni euristica],
  image("../images/approx_all_heuristics_vs_ratio.png")
) <approx_all_heuristics_vs_ratio>

== Analisi delle performance

Per valutare le prestazioni dell'implementazione, sono stati condotti benchmark sulle stessa istanze utilizzate nella @data-gen. 

Nella Figura 7 viene mostrato il tempo di esecuzione totale delle prime fasi dell'algoritmo, ovvero il calcolo delle SCC, del backbone e delle WCC, al variare del rapporto clausole/variabili e dal numero di variabili. Si può notare come il tempo di esecuzione aumenti con il numero di variabili, ed inoltre il tempo impiegato per istanze con rapporto clausole/variabili $>2$ è superiore a quello impiegato per istanze con rapporto clausole/variabili $<2$. Inoltre il tempo di esecuzione di queste prime fasi è nettamente inferiore al tempo utilizzato dalla fase di assegnamento guidato dalle euristiche, che è quella più costosa.

Nella figura 8 invece riportato il tempo impiegato dall'euristica 4, per le altre euristiche l'heatmap è simile, ma con tempi di esecuzione inferiori. Anche in questo caso si nota come il tempo di esecuzione aumenti con l'aumentare del numero di variabili. Invece al variare del rapporto il tempo di esecuzione si comporta in modo simile a quello mostrato nella @clingo_time, il picco del tempo di esecuzione si ha intorno al rapporto di 1.2 e si riduce più velocemente per rapporti più piccoli rispetto a rapporti più grandi. 

#table(
  columns: 2,
  inset: 0pt,
  stroke: none,
  column-gutter: 15pt,
  
  figure(
    caption: [Heatmap del tempo di esecuzione totale delle prime fasi dell'algoritmo, al variare del rapporto clausole/variabili e dal numero di variabili],
    image("../images/time_taken_by_first_phases.png", width: 150%)
  ),
  figure(
    caption: [
      Heatmap del tempo di esecuzione dell'euristica 4, al variare del rapporto clausole/variabili e dal numero di variabili
    ],
    image("../images/time_taken_by_heuristic4.png", width: 150%)
  ),
)

#v(10pt)

Per confrontare il tempo di esecuzione delle 4 euristiche sono state generate 200 istanze con un numero di variabili che va da 1000 a 25000, e con un rapporto clausole/variabili di $1.8$. I risultati sono mostrati nella @heuristics_time_comparison, l'euristica 4 è quella che impiega più tempo in assoluto, quasi 100 volte più delle altre euristiche, il calcolo delle raggiungibilità ad ogni iterazione risulta quindi molto costoso anche se permette di avvicinarsi maggiormente all'ottimo.

#figure(
  caption: [Confronto del tempo di esecuzione delle 4 euristiche al variare del numero di variabili, scala doppiamente logaritmica],
  image("../images/time_vs_num_vars_all_heuristics.png", width: 100%)
) <heuristics_time_comparison>

Sono stati quindi condotti benchmark su istanze più grandi per le prime tre euristiche, con un numero di variabili che va da 1000 a 1000000, e con un rapporto clausole/variabili di $1.8$. 

Nella @fast_heuristics_time_comparison viene mostrato il confronto del tempo di esecuzione delle 3 euristiche più veloci, al variare del numero di variabili, con una scala lineare a sinistra e una scala doppiamente logaritmica a destra. Si nota come verso le $10^5$ variabili la pendenza delle rette nel grafico con scala doppiamente logaritmica aumenti. Il punto corrisponde a quando il limite di memoria scelto viene superato e quindi è necessario suddividere le query di raggiungibilità in più chunk, questo comporta un aumento del tempo di esecuzione, ma permette di scalare a istanze più grandi. Inoltre è interessante calcolare la pendenza delle rette prima e dopo questo punto, infatti se il tempo di esecuzione è un polinomio del tipo $t = c*n^k$ allora la pendenza della retta in scala logaritmica è $k$:

$
  log(t) = log(c * n^k) = log(c) + k * log(n)
$

Nella @time_heuristics_pendencies vengono riportati i valori stimati per la pendenza delle rette prima e dopo il punto in cui il numero di chunk è maggiore di 1. 

Prima di questo punto il regime è molto vicino a quello lineare, mentre dopo questo punto la pendenza aumenta, ma rimane comunque inferiore a 2, quindi il tempo di esecuzione sembra scalare in modo sub-quadratico anche per istanze molto grandi.

Dai test effettuati l'euristica 2  risulta essere la più veloce, subito seguita dall'euristica 3 e poi dall'euristica 1.

#figure(
  kind: image,
  caption: [
    Confronto del tempo di esecuzione delle 3 euristiche più veloci al variare del numero di variabili. Sulla destra scala doppiamente logaritmica
  ],
  table(
    columns: 2,
    inset: 0pt,
    stroke: none,
    column-gutter: 15pt,

    image("../images/time_vs_num_vars_fast_heuristics_linear.png", width: 140%),

    image("../images/time_vs_num_vars_fast_heuristics.png", width: 140%)
  )
) <fast_heuristics_time_comparison>

#figure(
  caption: [Valori stimati per la pendenza delle rette prima e dopo il punto in cui il numero di chunk è maggiore di 1],
  table(
    columns: 3,
    [], [1 chunk], [>1 chunk],
    [Heuristic 1], [1.063], [1.745],
    [Heuristic 2], [1.060], [1.723],
    [Heuristic 3], [1.137], [1.837]
  )
) <time_heuristics_pendencies>


= Possibili miglioramenti

Il metodo con cui sono state generate le istanze tende a creare una grande componente debolmente connessa, quindi dopo poche iterazioni di assegnazioni delle variabili rimane un unica WCC e la parallelizzazione viene a meno. Per ovviare a questo problema, si potrebbe pensare ad un metodo per assegnare più variabili in ogni iterazione in un singolo WCC e quindi gestire in modo corretto gli eventuali conflitti. Se invece l'obbiettivo è quello di raggiungere una migliore approssimazione a discapito del tempo di esecuzione una beam search potrebbe essere una buona soluzione, la ricerca può essere eseguita in parallelo e guidata dalle stesse euristiche.

= Valutazioni e osservazioni

L'euristica 4, che prevede il ricalcolo dinamico della raggiungibilità, è quella che si avvicina maggiormente all'ottimo, tuttavia questa euristica è anche quella che impiega più tempo in assoluto, quasi 100 volte più delle altre euristiche, il calcolo delle raggiungibilità ad ogni iterazione risulta quindi molto costoso. L'euristica 2 e 3 hanno un comportamento per quanto riguarda il grado di approssimazione ma l'euristica 2 è significativamente più veloce dell'euristica 3, quindi sembra essere la scelta migliore se si vuole un buon compromesso tra qualità della soluzione e tempo di esecuzione. L'euristica 1, che seleziona un nodo sorgente, è quella che si discosta maggiormente dall'ottimo e impiega più tempo rispetto all'euristica 2, quindi sembra essere la scelta peggiore tra le 4 euristiche.


= Guida all'uso
Per compilare è sufficiente eseguire `make`, dopo la compilazione, si otterrà un eseguibile chiamato `fix`, che può essere utilizzato per risolvere istanze di 2-SAT e trovare un fix-set approssimato.

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
