#import "lib.typ": *
#import "@preview/lovelace:0.3.0": *
#import "@preview/fletcher:0.5.8": diagram, node, edge, shapes


#show: ams-article.with(
  paper-size: "a4",
  title: [On the Connection between Spectral Graph Theory and the Weisfeiler-Lehman Algorithm ],
  abstract: [This work explores the fundamental connections between spectral graph theory and the Weisfeiler-Lehman (WL) algorithm in the context of graph isomorphism testing. We begin by establishing the theoretical foundations of graph theory, the graph isomorphism problem, and its computational complexity. We then examine the Weisfeiler-Lehman algorithm, a powerful combinatorial method for graph isomorphism testing that iteratively refines vertex colorings based on neighborhood information. The analysis proceeds to investigate spectral graph theory, focusing on the Laplacian matrix and its spectrum as tools for analyzing graph structure. The key result reported is the detailed analysis of how a spectral oriented pre-coloring can enhance the expressiveness of the WL algorithm. We show that by initializing the WL algorithm with colorings based on the spectrum the resulting Spectral WL algorithm achieves strictly greater expressiveness than the standard 1-WL method.],
  authors: (
    (
      name: "Leonardo Danelutti",
      organization: [Università di Udine],
      email: "danelutti.leonardo@spes.uniud.it",
    ),
  ),
  supervisors: (
    (
      name: "Riccardo Romanello",
      organization: [Università di Udine],
    ),
    (
      name: "Alberto Policriti",
      organization: [Università di Milano],
    ),
    // Add more supervisors if needed
  ),
  bibliography: bibliography("refs.bib"),
)

= Graphs

A graph is a mathematical structure consisting of a set of vertices (also called nodes) and a set of edges that connect pairs of vertices.  This section provides the definition of a graph and some basic concepts that will be useful later on.

#definition[
An *undirected graph* $G = (V, E)$ is defined by a finite set of vertices $V$ and a set of edges $E subset.eq {{u, v} | u, v in V}$, where each edge represents a symmetric relationship between two vertices. In contrast, a *directed graph* (or digraph) $G = (V, E)$ has edges $E subset.eq V times V$ that are ordered pairs, meaning that the edge $(u, v)$ is distinct from $(v, u)$.
]

We say that two vertices $u$ and $v$ are *adjacent* (or *neighbors*) if there is an edge connecting them.
A graph may contain *self-loops*, which are edges that connect a vertex to itself. 

#definition[
 Given an undirected graph $G=(V, E)$ the edge ${v, v'} in E$ is a self-loop if and only if $v = v'$. Similarly, in a directed graph, a self-loop is an edge of the form $(v, v)$.
 A graph is called *simple* if it contains no self-loops.
]

From now on we will only consider simple undirected graphs if not specified otherwise.

The neighborhood of a vertex is the set of all its adjacent vertices. 

#definition[
 Given an undirected graph $G=(V, E)$, the *neighborhood* of a vertex $v in V$, written $N(v)$, is defined as:
  $ N(v) = {u in V | {v, u} in E} $
]

The degree of a vertex is the number of edges adjacent to it.

#definition[
  Given an undirected graph $G=(V, E)$, the *degree* of a vertex $v in V$ in a graph, denoted by $deg(v)$, is defined as:
  $ deg(v) = |N(v)| $
]

Consider the following example: Let $G = (V, E)$ where $V = {1, 2, 3, 4}$ and $E = {{1,2}, {2,3}, {3,4}, {4,1}, {2,4}}$ as in @simple-graph. This simple undirected graph has $deg(1) = 2$, $deg(2) = 3$, $deg(3) = 2$, and $deg(4) = 3$. The neighborhood of vertex 2 is $N(2) = {1, 3, 4}$.

#let draw-graph(nodes, node-positions, edges) = {
  diagram({
    for (i, n) in nodes.enumerate() {
      node(node-positions.at(i), str(n), shape: circle, stroke: 0.5pt, label: n)
    }

    for (u, v) in edges {
      edge(node-positions.at(nodes.position(n => n == u)), node-positions.at(nodes.position(n => n == v)), "-")
    }
  })
}

#let V-1 = (1, 2, 3, 4)
#let  VP-1 = ((0, 0), (1, 0), (1, 1), (0, 1))
#let E1 = ((1, 2), (2, 3), (3, 4), (4, 1), (2, 4))

#figure(
  kind: image,
  caption: [Example of a graph],
  draw-graph(V-1, VP-1, E1)
)<simple-graph>

In order to represent a graph we can use the adjacency matrix. Each entry $(u, v)$ of the matrix indicates whether there is an edge between vertices $u$ and $v$.

#definition[
The *adjacency matrix* $A^G$ of an undirected graph $G=(V, E)$ with $n = |V|$ vertices is an $n times n$ matrix where:

$
A^G (u, v) = cases(
  1 "  if" {u, v} in E,
  0 "  otherwise"
)
$
]
If the graph $G$ is clear from the context or irrelevant the superscript is omitted. Note that for undirected graphs the adjacency matrix is symmetric, and for simple graphs the entries on the main diagonal are all zero.

For the graph in @simple-graph, the adjacency matrix is:

$
A = mat(
  0, 1, 0, 1;
  1, 0, 1, 1;
  0, 1, 0, 1;
  1, 1, 1, 0
)
$

The adjacency matrix provides a convenient algebraic representation that enables the use of linear algebra techniques in graph analysis, which forms the foundation for spectral graph theory.

It can also be useful to assign each vertex a color (or label) from a set, in order to represent additional information about the vertices.

#definition[
  A *vertex-colored graph* $G=(V, E, lambda)$ is a graph $(V, E)$ together with a coloring function $lambda : V -> cal(C)$ that assigns to each vertex a color from a set $cal(C)$.
]

We want to be able to talk about "strategies" to color the vertices of a given graph, we call such strategies a *graph coloring*. Thus a graph coloring $C$ is a mapping from a vertex and its graph to a color, from a known set of colors. It will always be clear from the context on which graph the coloring is defined.

Given a coloring of a graph, we say that a coloring $C$ *refines* another coloring $D$ if every color class of $C$ is a subset of a color class of $D$, i.e. if two vertices have the same color in $C$ they must also have the same color in $D$.

#definition[
  Given a graph $G=(V,E)$ we say that the coloring $C$ *refines* coloring $D$ if:
  $ forall u, v in V space space space C(u) = C(v) => D(u) = D(v) $
]

#pagebreak()

= The graph isomorphism problem <isomorphism-problem>

When dealing with graphs, it is often useful to determine whether two graphs are structurally identical, regardless of the names given to the vertices or their ordering. For example in @iso-graphs, the two graphs appear different at first glance due to how their vertices are placed and the labels of the vertices, but with a proper renaming, they can be shown to be identical in structure. This leads us to the concept of graph isomorphism.

#let V-iso = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
#let E-iso = ((1,2),(1,4),(1,5),(2,3),(3,7),(3,4),(5,6),(5,8),(6,7),(7,8),(9,10),(9,12),(9,13),(10,11),(11,15),(11,12),(13,14),(13,16),(14,15),(15,16))
#let VP-iso = ((0, 0), (3*3/4, 0), (3*3/4, 3*3/4), (0, 3*3/4), (1*3/4, 1*3/4), (2*3/4, 1*3/4), (2*3/4, 2*3/4), (1*3/4, 2*3/4), (4, 1), (5, 2), (6, 1), (5, 0), (5, 1), (6, 0), (7, 1), (6, 2))

#figure(
  caption: [Two graphs],
  draw-graph(V-iso, VP-iso, E-iso)
) <iso-graphs>

#definition[
Two graphs $G_1 = (V_1, E_1)$ and $G_2 = (V_2, E_2)$ are *isomorphic*, denoted by $G_1 tilde.equiv G_2$, if there exists a bijection $sigma : V_1 arrow V_2$ such that for every pair of vertices $u, v in V_1$, the edge ${u, v} in E_1$ if and only if ${sigma (u), sigma (v)} in E_2$. The function $sigma$ is called an *isomorphism* between the two graphs.
]

In @iso-graphs-map we can see the same two graphs from the previous example, the red arrows indicate the application of $f$ that maps each vertex in the first graph to its corresponding vertex in the second graph. All the relation between vertices are preserved, thus the two graphs are isomorphic.

#let V-iso = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
#let E-iso = ((1,2),(1,4),(1,5),(2,3),(3,7),(3,4),(5,6),(5,8),(6,7),(7,8),(9,10),(9,12),(9,13),(10,11),(11,15),(11,12),(13,14),(13,16),(14,15),(15,16))
#let VP-iso = ((0, 0), (3*3/4, 0), (3*3/4, 3*3/4), (0, 3*3/4), (1*3/4, 1*3/4), (2*3/4, 1*3/4), (2*3/4, 2*3/4), (1*3/4, 2*3/4), (4, 1), (5, 2), (6, 1), (5, 0), (5, 1), (6, 0), (7, 1), (6, 2))

// Isomorphism mapping: 1->9, 2->10, 3->12, 4->13, 5->14, 6->16, 7->15, 8->11
#let iso-mapping = ((1,9), (2,12), (3,11), (4,10), (5,13), (6,14), (7,15), (8,16))

// TODO: colora i nodi

#figure(
  caption: [Two isomorphic graphs with the isomorphism mapping],
  diagram({
    // Define colors for each equivalence class under the isomorphism
    let node-colors = (
      "1": rgb("#2941f9ee"),     // 1 -> 9
      "2": rgb("#2972f9ee"),     // 2 -> 12
      "3": rgb("#29a2f9ee"),     // 3 -> 11
      "4": rgb("#29d2f9ee"),     // 4 -> 10
      "5": rgb("#f94229ee"),     // 5 -> 13
      "6": rgb("#f97229ee"),     // 6 -> 14
      "7": rgb("#f9a229ee"),     // 7 -> 15
      "8": rgb("#f9d229ee"),     // 8 -> 16
      "9": rgb("#2942f9ee"),     // 9 <- 1
      "10": rgb("#29d2f9ee"),    // 10 <- 4
      "11": rgb("#29a2f9ee"),    // 11 <- 3
      "12": rgb("#2972f9ee"),    // 12 <- 2
      "13": rgb("#f94229ee"),    // 13 <- 5
      "14": rgb("#f97229ee"),    // 14 <- 6
      "15": rgb("#f9a229ee"),    // 15 <- 7
      "16": rgb("#f9d229ee")     // 16 <- 8
    )
    
    // Draw vertices and edges for both graphs
    for (i, n) in V-iso.enumerate() {
      node(VP-iso.at(i), str(n), shape: circle, stroke: 0.5pt, fill: node-colors.at(str(n)), label: n)
    }
    for (u, v) in E-iso {
      edge(VP-iso.at(V-iso.position(n => n == u)), VP-iso.at(V-iso.position(n => n == v)), "-")
    }
    
    // Draw red curved arrows showing the isomorphism mapping
    for (u, v) in iso-mapping {
      edge(VP-iso.at(V-iso.position(n => n == u)), VP-iso.at(V-iso.position(n => n == v)), "->", stroke: red.transparentize(75%) + 0.8pt, bend: 30deg)
    }
  })
) <iso-graphs-map>

But how complex is to determine whether two graph are "equal" algorithmically? The graph isomorphism problem is the computational challenge of determining whether two finite graphs are isomorphic. While it is known that the problem is in NP (given the vertices map it is easy to verify that the relations on them are preserved), it is not known to be NP-complete or in P. The graph isomorphism problem is one of the few problems with this properties and thus is one of the candidates for being in the NP-intermediate class@grohe2021recentadvancesgraphisomorphism.

Even if a polynomial-time algorithm for the general graph isomorphism problem is not known, there are efficient algorithms for specific classes of graphs, such as trees or planar graphs@Hopcroftlinearplanarisomorphism. Recently, László Babai proposed a quasipolynomial-time algorithm for solving the problem@babaiquasipolynomialisomorphism.

Since determining graph isomorphism is computationally challenging we may want to use some test that can quickly determine if two graphs are definitely not isomorphic, even if it cannot always confirm isomorphism. One such test is, for example, comparing the histogram#footnote[The word "histogram" is used to refer to the multiset of colors.] of the degrees of the vertices in both graphs, i.e. given $G_1=(V_1, E_1)$ and $G_2=(V_2, E_2)$ checking whether:

$ {{deg(v) | v in V_1}} = {{deg(v) | v in V_2}} $

where with ${{}}$ we denote a multiset.

If the histograms differ it is easy to see that graphs cannot be isomorphic. However, if they are the same, the graphs may or may not be isomorphic.

This is an example of a *graph invariant*, meaning a property that is preserved under isomorphism, more formally:

#definition[Given the set of all graphs $cal(G)$, the function $f: cal(G) -> S$ is call *graph invariant* if: $ forall G_1, G_2 in cal(G) space space space G_1 tilde.equiv G_2 => f(G_1) = f(G_2) $
]

Some graph invariants are more powerful than others, meaning that they can distinguish between a larger set of non-isomorphic graphs. The degree histogram is not a very powerful invariant, as there exist many pairs of non-isomorphic graphs that share the same degree histogram. In order to compare the power of different graph invariants the notion of *expressivness* is used.

#definition[
  A graph invariant $f$ is *at least as expressive* as another graph invariant $g$ if:
  $ forall G_1, G_2 in cal(G) space space space g(G_1) = g(G_2) => f(G_1) = f(G_2) $
  That is, whenever $g$ cannot tell two graphs apart, $f$ also cannot. If there exist graphs $G_1$ and $G_2$ such that $g(G_1) = g(G_2)$ but $f(G_1) eq.not f(G_2)$ then $f$ is *strictly more expressive* than $g$.
]

We want to find a graph invariant that is as expressive as possible, without being too computationally expensive.

When dealing with graphs colorings, we may want that the colors are preserved under isomorphism as well.

#definition[
  Let $G_1 = (V_1, E_1)$ and $G_2 = (V_2, E_2)$ two isomorphic graphs, with $sigma : V_1 arrow V_2$ an isomorphism between them. Given a coloring $C$, we say that $C$ is *permutation equivariant* if
   $ forall v in V_1 space space  C(v) = C(sigma(v))  $
]

#pagebreak()

= The Weisfeiler-Lehman algorithm

The Weisfeiler-Lehman algorithm (or WL algorithm) is a combinatorial algorithm used to test graph isomorphism. It was introduced by Boris Weisfeiler and Andrei Lehman in the 1960s@weisfeiler1968reduction and has since become a fundamental tool in graph theory and computer science. Each vertex in the graph is assigned a color (or label), and the algorithm iteratively refines these colors based on the colors of neighboring vertices until a stable coloring is reached. If two graphs have different color distributions at any iteration, they are not isomorphic. 

There are many variants of the algorithm, like the $k$-dimensional Weisfeiler-Lehman algorithms ($k$-WL), that are more expressive than the standard (1-dimensional) version. In the next sections we will focus on the 1-WL algorithm, and later we will see how it can be generalized to higher dimensions.

== 1-WL

The Weisfeiler-Lehman algorithm, also known as color refinement, start with an initial coloring of the vertices of a graph, which is often uniform (i.e., all vertices have the same color). At each iteration the color of each vertex is updated based on its current color and the multiset of colors of its neighbors. This process continues until the coloring stabilizes, meaning that no further changes occur in an iteration. The pseudocode for the 1-WL algorithm is shown in @WL-1, where _hash_ is a function that encodes the input into a unique color.

#figure(
  kind: "algorithm",
  supplement: [Algorithm],
  pseudocode-list(booktabs: true, stroke:none, numbered-title: [1-WL (color refinement)])[
    *Input:* A vertex-colored graph $G = (V, E, lambda)$ \
    *Output:* A coloring $cal(C)$ 
    + $cal(C)^0 (v) = "hash"(lambda (v)) $ for all $v in V$
    + *do*
      + $cal(C)^i (v) = "hash"(cal(C)^(i-1) (v), {{cal(C)^(i-1) (u) | u in N(v)}}) " for all" v in V(G)$
    + *while* $cal(C)^i != cal(C)^(i-1)$
    + *return* ${{cal(C)^i (v) | v in V}}$
  ]
) <WL-1>

Using the notation in @WL-1, we call $cal(C)^i (v)$ the coloring obtained at the $i$-th iteration of the algorithm on vertex $v$ and $cal(C) (v)$ the final stable coloring of vertex $v$.

#figure(
  image("wl-1.png", width: 100%),
  caption: [Example of each iteration of the 1-WL algorithm, from the top left to the bottom right.],
) <WL-example>

In @WL-example is depicted an example of the 1-WL algorithm. In the first iteration, colors are assigned based on the degree of each vertex. If we were to stop the algorithm at this point, we would obtain the same invariant as the degree histogram discussed in @isomorphism-problem. However, the algorithm continues to refine the colors in subsequent iterations by considering the colors of neighboring vertices, leading to a more expressive invariant.

At each iteration, the coloring is refined while preserving the isomorphism invariant property, since the color updates are based on vertex neighborhoods, which are preserved under graph isomorphism.

The $1 dash "WL"$ test can be computed efficiently in $O(m log n)$ time@CARDON198285, where $n$ is the number of vertices and $m$ is the number of edges in the graph. This efficiency makes it suitable for practical applications in graph isomorphism testing and related problems. Of course the algorithm cannot distinguish all non-isomorphic graphs but it is quite powerful: it can distinguish all between all forests and more surprisingly, for sufficiently large $n$, the fraction of graphs of $n$ vertices which $1 dash "WL"$ fails to identify is extremely small@bes. There are classes of graphs on which the algorithm fails, for example regular graphs with the same degree and number of vertices, and even small examples like the two graphs in @WL-fail.

// exagon
#let V-sc1 = (1, 2, 3, 4, 5, 6)
#let VP-sc1 = ((0, 1), (calc.sqrt(3)/2, 0.5), (calc.sqrt(3)/2, -0.5), (0, -1), (-calc.sqrt(3)/2, -0.5), (-calc.sqrt(3)/2, 0.5))
#let E-sc1 = ((1,2),(2,3),(3,4),(4,5),(5,6),(6,1))

// two triangles
#let V-sc2 = (1, 2, 3, 4, 5, 6)
#let VP-sc2 = ((0, -0.8), (-1, 0), (0, 0.8), (0.75, -0.8), (1.75, 0), (0.75, 0.8))
#let E-sc2 = ((1,2),(2,3),(3,1),(4,5),(5,6),(6,4))

#figure(
  kind: image,
  caption: [Two non-isomorphic graphs that 1-WL fails to distinguish],
  table(
    columns: 2,
    stroke: (x, y) => if x == 1 { (left: 1pt) } else { none },
    draw-graph(V-sc1, VP-sc1, E-sc1),
    draw-graph(V-sc2, VP-sc2, E-sc2)
  )
) <WL-fail>

The connection between the Weisfeiler-Lehman algorithm and Graph Neural Networks (GNNs) has been extensively studied in recent years. Graph Neural Networks (GNNs) are specialized neural architectures designed for task whose input are graphs. In a Message Passing GNN (MPGNN), each node aggregates messages from adjacent nodes, usually through a permutation-invariant function such as sum, mean, or max; and then updates its representation using a learnable transformation. This iterative message-passing mechanism closely mirrors the refinement process of the Weisfeiler-Lehman algorithm: in both cases, a node's state is updated using information about its neighborhood. The key difference is that 1-WL performs this aggregation through a fixed, discrete hashing procedure, while MPGNNs learn continuous update functions from data. Despite this distinction, their expressive power is equivalent: standard MPGNNs cannot distinguish any pair of non-isomorphic graphs that 1-WL also fails to distinguish@Morris2019WeisfeilerAL.

== k-WL

The $k$-dimensional Weisfeiler-Lehman algorithm ($k$-WL) is a generalization of the 1-WL algorithm that operates on $k$-tuples of vertices instead of individual vertices. This allows the algorithm to capture more complex structural information about the graph, making it more expressive than the 1-WL variant. In this section we will describe the $k$-WL variant that is call _folklore_ in the literature. 

The algorithm starts with an initialization phase where all tuples are colored by a function _init_ in such a way that tuples $arrow(u) = (u_1, u_2, ..., u_k)$ and $arrow(v) = (v_1, v_2, ..., v_k)$ of verticies of graphs $G$ and $H$ respectively receive the same color if and only if the mapping $u_i mapsto v_i$ for $i = 1, ..., k$ is an isomorphism between the subgraphs of $G$ and $H$ induced by the vertices in the tuples.

In the $k$-WL algorithm, at each iteration, the color of each $k$-tuple of vertices is updated based on its current color and the colors of all its "neighbors" tuples. Here a neighbor tuple is obtained by replacing one vertex in the original tuple with another vertex from the graph, more formally:

#definition[
  Given a tuple $arrow(v) = (v_1, v_2, ..., v_k)$ and a vertex $w$, we define the tuple $arrow(v)_([i] arrow.l w)$ as the tuple obtained by replacing the $i$-th element of $arrow(v)$ with $w$, i.e.:
  $ arrow(v)[i] arrow.l w = (v_1, v_2, ..., v_(i-1), w, v_(i+1), ..., v_k) $
]

In @WL-k we can see how the colors are updated at each iteration.

#figure(
  kind: "algorithm",
  supplement: [Algorithm],
  pseudocode-list(booktabs: true, stroke:none, numbered-title: [k-WL])[
    *Input:* A graph $G = (V, E)$ \
    *Output:* A coloring $cal(C)$ 
    + $cal(C)^0 (arrow(v)) = "init"(G, arrow(v)) $ for all $arrow(v) in V^k$
    + *do*
      + $cal(N) (arrow(v), w) = (cal(C)^(i-1) (arrow(v)[1] arrow.l w), dots, cal(C)^(i-1) (arrow(v)[k] arrow.l w))" for all" arrow(v) in V(G)^k "and" w in V$
      + $cal(C)^i (arrow(v)) = "hash"(cal(C)^(i-1) (arrow(v)), {{cal(N) (arrow(v), w) | w in V}}) "    for all" arrow(v) in V^k$
    + *while* $cal(C)^i != cal(C)^(i-1)$
    + *return* ${{cal(C)^i (arrow(v)) | arrow(v) in V^k}}$
  ]
) <WL-k>

It is important to note that only in the initialization step the information about the graph edges is used.

It can be proven that $k$-WL with $k eq 1$ can distinguish exactly the same pairs of non-isomorphic graphs as the color refinement procedure of 1-WL. Furthermore, for $k >= 2$, the $k$-WL algorithm is strictly more expressive than the $(k-1)$-WL variant@CaiLowerBound. However, as $k$ increases, the computational complexity of the algorithm also increases significantly, making it less practical for large graphs. If we chose $k = n$ where $n$ is the number of vertices in the graph, then the algorithm becomes a test for isomorphism, but at the cost of exponential time complexity.

#pagebreak()

= Spectral graph theory <spectral-graph-theory>

*Spectral theory* is a branch of mathematics that studies matrices  (and linear operators) by examining their eigenvalues and eigenvectors, collectively known as the *spectrum*. Rather than focusing on the explicit entries of a matrix or the analytic form of an operator, spectral theory seeks to understand its intrinsic properties, e.g. how it acts or transforms a space, through its spectral characteristics. 

*Spectral graph theory* extends these ideas to the study of graphs. A graph can be represented algebraically through matrices such as the adjacency matrix, whose spectra encode essential features of the graph's structure. The eigenvalues and eigenvectors of these matrices reflect properties such as connectivity, clustering, and diffusion processes on the graph. In this way, spectral graph theory allows graphs to be analyzed through the language of linear algebra.

== The Laplacian matrix

The most simple way to represent a graph is through its adjacency matrix. The spectral properties of such matrix reveal important information about the graph, as upper and lower bounds to the cromatic number, number of closed walks of a given length and many more@TheLaplacianspectrumofgraphs; but one of the most useful representations is through the *Laplacian matrix*. This matrix, denoted by $L$, is defined as:

$ L = D - A $

Where $D$ is the *degree matrix*, a diagonal matrix where each entry $D(i, i) = |N(i)|$. Since $D$ and $A$ are symmetric matrices, $L$ is also symmetric, and thus, from the _spectral theorem_, it has real eigenvalues, that we call $lambda_i$ and orthogonal eigenvectors $phi.alt_i$. 

The Laplacian matrix has several important properties that make it particularly useful for analyzing graphs. For example, the number of connected components in a graph is equal to the multiplicity of the eigenvalue 0. The second smallest eigenvalue, known as the algebraic connectivity or Fiedler value, provides insights into the graph's connectivity and robustness. The corresponding eigenvector can be used for graph partitioning and clustering@TheLaplacianspectrumofgraphs.

The Laplacian matrix owes its name to its analogy with the Laplace operator in continuous domains, which measures how the value of a function at a point differs from its average value in a small neighborhood around that point. In the context of graphs, the Laplacian matrix captures how the value at a vertex differs from the average value of its neighbors, making it a discrete analogue of the continuous Laplace operator. In fact:

$ (L f)(v) = sum_(u in N(v)) (f(v) - f(u)) $
Where $f$ is a function defined on the vertices of the graph. This property makes the Laplacian matrix particularly useful for studying diffusion processes, random walks, and other dynamic phenomena on graphs.

== Heat kernel <heat-kernel>

The heat kernel is a fundamental solution to the heat equation on a graph, which describes how heat diffuses over time across the vertices of the graph. The Laplacian matrix is used instead of the Laplacian operator in the heat equation:

$ (partial H_t)/ (partial t) = - L H_t $

Where $H_t$ is the heat kernel at time $t$. When each vertex is initialized with a unit of heat (i.e. $H_0 = I$ where $I$ is the identity matrix), the solution to this equation is given by:

$ H_t = e^(-t L) $

By diagonalizing the Laplacian matrix we get that

$ H_t (u, v) = sum_(i=1)^(|V|) e^(- lambda_i t) phi.alt(u) phi.alt(v) $

Where $lambda_i$ and $phi.alt_i$ are the eigenvalues and eigenvectors of the Laplacian matrix. 

For each row $u$, $H_t (u, v)$ represents the amount of heat that has diffused from vertex $u$ to vertex $v$ after time $t$; from the beginning of the diffusion process, when the node $u$ had heat 1 and all other nodes had heat 0. When t is close to 0 the kernel is affected by the local structure while for large values of $t$ the global structure of the graph becomes the dominant structure.

 
== Co-spectrality and ismorphism

If two graph have the same spectrum they are called *co-spectral*. Spectral properties of graphs are invariant under isomorphism, meaning that if two graphs are isomorphic they are co-spectral, and so they can be used as isomorphism tests. However, the converse is not true: there exist non-isomorphic graphs that share the same spectrum. One simple example is the one in @co-spectral-graphs.

#figure(
  caption: [Two co-spectral but non-isomorphic graphs],
  kind: image,
  table(
    columns: 2,
    stroke: none,
    gutter: 30pt,
    draw-graph(
      (1, 2, 3, 4, 5, 6), 
      ((0, 1), (1, 0), (2, 1), (1, 2), (3,0), (3,2)), 
      ((1,2),(2,3),(3,4),(4,1),(3,5),(5,6),(6,3))
    ),
    draw-graph(
      (1, 2, 3, 4, 5, 6), 
      ((0, 1), (1, 0), (2, 1), (1, 2), (1,1), (3,1)), 
      ((1,2),(2,3),(3,4),(4,1),(4,5),(5,2),(3,6))
    ),
  )
) <co-spectral-graphs>

They are clearly not isomorphic, but both have the characteristic polynomial (with respect to the Laplacian) $p(x) = lambda^6 -14lambda^5 + 73lambda^4 -176lambda^3 + 192lambda^2 -72lambda$ and thus the same spectrum. More graph invariant based on spectrum have been proposed, like the Fürer spectral invariant@FURER20102373, but they cannot distinguish all non-isomorphic graphs.

== Computation of the spectrum

There are several methods to efficiently compute the spectra of a matrix.

For small to medium-sized graphs, direct methods such as the QR algorithm can be used to compute all eigenvalues and eigenvectors of the Laplacian matrix in $O(n^3)$. The QR algorithm is an iterative method that decomposes a matrix $A$ into a product of an orthogonal matrix $Q$ and an upper triangular matrix $R$ (i.e., $A = Q R$). Then the matrix is updated as $A' = R Q$. Repeating this process converges to a triangular matrix whose diagonal entries are the eigenvalues of the original matrix.

For larger graphs, iterative methods like the Lanczos algorithm or the Arnoldi iteration are more suitable, as they can efficiently compute a subset of the spectrum, particularly the largest or smallest eigenvalues and their corresponding eigenvectors. Other methods work better for sparse matrices, which are common in graph representations, and can significantly reduce computational time and memory usage.

#pagebreak()

= 1-WL with spectral pre-coloring

In this section we will explore how the expressiveness of the 1-WL algorithm can be enhanced by using pre-colorings, meaning how we assign an initial color to each vertex before running the algorithm. The main results, by Feldman et al.@feldman2022weisfeilerlemaninfinitespectral, are:
+ 1-WL with a pre-coloring $C_1$ is at least as expressive as 1-WL with a pre-coloring $C_2$ if $C_1$ refines $C_2$ and $C_1$ is permutation equivariant.
+ The expressive power of $1 dash "WL"$ can be improved ad infinitum by a sequence of equivariant pre-colorings
\

We call $1 dash C"WL"$ the 1-WL algorithm with pre-coloring $C$.

#theorem[
  Let $C_1$, $C_2$ be two colorings s.t. $C_1$ refines $C_2$ and $C_1$ is permutation equivariant. Accordingly, $1 dash C_1"WL"$ is at least as expressive as $1 dash C_2"WL"$.
] <color-expr>

#proof-outline[
First it is shown that if two graphs are isomorphic then their histograms of $1 dash C_1"WL"$ are the same. Then it is shown that whenever two graphs are distinguished by $1 dash C_2"WL"$ they are also distinguished by $1 dash C_1"WL"$.

\
+ Given two isomorphic graphs $G_1$ and $G_2$ with isomorphism $sigma : V_1 -> V_2$ and a permutation equivariant coloring $C_1$ it can be shown that, by induction on the number $n$ of iteration of 1-WL, for each $v_1 in V_1$ and $v_2 in V_2$ s.t. $sigma (v_1) = v_2$: 
  $ cal(C)_(1 dash C_1"WL")^n (v_1) = cal(C)_(1 dash C_1"WL")^n (v_2) $ Meaning that for each iteration of 1-WL the colors of each two vertices mapped by the isomorphism are the same. The induction exploits the fact that $C_1$ is permutation equivariant.
  \

+ Given two graph $G_1$ and $G_2$ and two colorings $C_1$ and $C_2$ such that $C_1$ refines $C_2$, it can be shown that, by induction on the number $n$ of iteration of 1-WL, for each $v_1 in V_1$ and $v_2 in V_2$:
  $ cal(C)_(1 dash C_1"WL")^n (v_1) = cal(C)_(1 dash C_1"WL")^n (v_2) => cal(C)_(1 dash C_2"WL")^n (v_1) = cal(C)_(1 dash C_2"WL")^n (v_2) $
  This can be done thanks to the refinement property of $1 dash "WL"$. It immediately follows that:
  $ cal(C)_(1 dash C_2"WL")^n (v_1) != cal(C)_(1 dash C_2"WL")^n (v_2) => 
  cal(C)_(1 dash C_1"WL")^n (v_1) != cal(C)_(1 dash C_1"WL")^n (v_2) $
  Which means that if two graph are distinguished by $1 dash C_2"WL"$ they are also distinguished by $1 dash C_1"WL"$.
]

For two coloring $C_1$ and $C_2$ that satisfy @color-expr in order to prove that $1 dash C_1"WL"$ is strictly more expressive than $1 dash C_2"WL"$ it is sufficient to find two graphs that are distinguished by $1 dash C_1"WL"$ but not by $1 dash C_2"WL"$.

\

To prove the second result stated at the beginning of the section the idea is to use colors obtained from higher dimensional WL algorithms as pre-colorings for the 1-WL algorithm. This is done by coloring each vertex $v$ with the final color of the $k$-tuple $(v, v, ..., v)$ after running the $k$-WL algorithm. 

#definition[
  The diagonal $k dash "WL"$ coloring of a graph vertices is defined to be $ Delta(k dash "WL")(v) = cal(C)_(k dash "WL")(v, dots, v) $
]

First it is shown that the diagonal coloring is as expressive as the full $k$-WL coloring and then it is shown that using the $ Delta(k dash "WL")$ coloring as a pre-coloring for the 1-WL algorithm the expressiveness can be improved up to isomorphism (by increasing $k$).

#theorem[
  Let $G_1$ and $G_2$ be two graphs. Their $Delta ("k-WL")$ histograms are equal $arrow.l.r.double.long$ their $cal(C)_(k dash"WL")$ histograms are equal.
] <diag-expr>

#proof-outline[
  #pad(left: 2em)[
    $arrow.long.double)$ When the coloring of $k dash"WL"$ stabilizes, we continue iterating, this will not change the colors of any tuples. At the start we know that there is a injective mapping $mu_1$ s.t. for all $x in V_1$ is true that $cal(C)_(k dash"WL")(x, dots, x) = cal(C)_(k dash"WL")(mu_1(x), dots, mu_1(x))$. Then after one iteration we know that ${{cal(C)_(k dash"WL")(x,dots,x, y) | y in V_1}} = {{cal(C)_(k dash"WL")(mu_1(x),..,mu_1(x), y) | y in V_2}}$ for all $x in V_1$  because of how $k dash"WL"$ is defined. Hence there is an injective mapping $mu_2$ s.t. for all $x, y in V_1$ is true that $cal(C)_(k dash"WL")(x, dots, x, y) = cal(C)_(k dash"WL")(mu_1(x), dots, mu_1(x), mu_2(y))$. By repeating this for k-1 iterations we arrive at the conslusion that ${{cal(C)_(k dash"WL")(arrow(v)) | arrow(v) in V_1^k}} = {{cal(C)_(k dash"WL")(arrow(v)) | arrow(v) in V_2^k}}$. By running $k dash"WL"$ after the colors have been stabilizes we have shown that the full coloring is encoded onto the diagonal coloring.
  ]

  #pad(left: 2em)[
    $arrow.long.double.l)$ Given $G_1$ and $G_2$ such that ${{cal(C)_(k dash"WL")(arrow(v)) | arrow(v) in V_1^k}} = {{cal(C)_(k dash"WL")(arrow(v)) | arrow(v) in V_2^k}}$ we want to show that ${{Delta(k dash"WL")(v) | v in V_1}} = {{Delta(k dash"WL")(v) | v in V_2}}$. From the initialization phase of $k dash "WL"$ it follows that if a tuple is colored with the same color as a diagonal tuple, then the first tuple is also a diagonal tuple. Since WL is a refinement process this holds throughout all the iterations. This means that other tuples that are not diagonal tuples do not count towards the histogram of the diagonal coloring.
  ]

]


#theorem[
  for any $k>=1$, $1 dash Delta (k+1 dash "WL")"WL"$ is strictly more expressive than $1 dash Delta (k dash "WL")"WL"$.
]

#proof-outline[
From @color-expr it follows that $1 dash Delta (k+1 dash "WL")"WL"$ is at least as expressive as $1 dash Delta (k dash "WL")"WL"$. To show that it is strictly more expressive it is sufficient to find two graphs that are distinguished by $1 dash Delta (k+1 dash "WL")"WL"$ but not by $1 dash Delta (k dash "WL")"WL"$. For any $k>=1$ there are two graphs $G_1$ and $G_2$ that are distinguished by $(k+1) dash "WL"$ but not by $k dash "WL"$@CaiLowerBound. From @diag-expr it follows that they are also distinguished by $1 dash Delta (k+1 dash "WL")"WL"$ and that their $Delta (k dash "WL")$ histograms are equal. It is only left to show that they are not distinguished by $1 dash Delta (k dash "WL")"WL"$, and it can be done by observing that an iteration of $1 dash "WL"$ does not change the color of any vertex (except for the marking/representation of the colors) because of how the initialization phase of $k dash "WL"$ is defined.

Since the coloring of $1 dash Delta (k dash "WL")"WL"$ does not change in any iteration and the histograms of $Delta (k dash "WL")$ are equal for $G_1$ and $G_2$, it follows that the histograms of $1 dash Delta (k dash "WL")"WL"$ are also equal for $G_1$ and $G_2$.
]

This shows that the expressiveness of 1-WL can be improved indefinitely by using proper permutation equivariant pre-colorings.

= Spectral pre-coloring

From the results in the previous section we know that the expressiveness of 1-WL can be improved by using a proper pre-coloring. In this section we will explore how spectral graph theory can be used to obtain such a pre-coloring. The coloring defined in Feldam et al.@feldman2022weisfeilerlemaninfinitespectral will be presented here, which makes use of the heat kernel of the graph as defined in @heat-kernel.

To calculate the pre-coloring first $m$ evenly space time points $t_1, dots, t_m$ are chosen in a logarithmic scale. For each time point $t_i$ the heat kernel $H_(t_i)$ is computed, and then for each vertex $v$ the value of the heat kernel at time $t_i$ is used to color the vertex like so: $(H_(t_1)(v, v), dots, H_(t_m)(v, v))$. As mentioned in @heat-kernel this can be taught of as the amount of heat left at node $v$ throughout time if initially only node $v$ had heat. In addition, we can chose a constant amount of quartiles $r$ from the row of u in the heat kernel (ignoring the elements on the main diagonal) and use them to further color the vertex, by appending $((q_(1_u)^(t_1), dots, q_(r_u)^(t_1)), dots, (q_(1_u)^(t_m), dots, q_(r_u)^(t_m)))$ to the previous coloring of the node. This can be thought of as the amount of heat at the other nodes during the diffusion process that started at node $v$. We call this coloring the *spectral pre-coloring* and the resulting algorithm *Spectral WL*.

\

// Examples
From looking at @spectral-precoloring we can intuitively see that _spectral WL_ is more expressive than 1-WL. The two graphs in the figure are indistinguishable by 1-WL: at the next step the blue nodes adjacent to the purple ones will change color and then the test will stop without finding any difference. With spectral pre-coloring, even choosing $m=1$ and $r=0$ the initial coloring is already enough to distinguish the two graphs, as the colors assigned to the vertices are different.

#figure(
  caption: [$1 dash "WL"$ indistinguishable graphs of the Decalin and Bicyclopentyl molecules. A the top the first round of $1 dash "WL"$, at the bottom the spectral pre-coloring with $m=1$ and $r=0$],
  image("precolor.png")
) <spectral-precoloring>

// Expressiveness
We now proof the result more formally.

#theorem[
  The spectral pre-coloring is permutation equivariant.
]

#proof-outline[
  We can say that two graphs are isomorphic if there exist a permutation matrix $P$ s.t.
  $ A^(G_1) = P A^(G_2) P^T $
  From that fact is is easy to see that the Laplacians of two graph are similar and thus have the sames spectrum. From the definition of the heat kernel it follows that:
  $ forall t space space H_t^(G_1) = P H_t^(G_2) P^T $
]

#theorem[
  Spectral WL is strictly more expressive than 1-WL.
]

#proof[
  From @color-expr it follows that Spectral WL is at least as expressive as 1-WL, since the spectral pre-coloring is permutation equivariant and any coloring refines the constant coloring. To show that it is strictly more expressive it is sufficient to find two graphs that are distinguished by Spectral WL but not by 1-WL. The two graphs in @spectral-precoloring are such an example.
]

Rattan and Seppelt@WeisfeilerLemanandGraphSpectra showed that the spectral pre-coloring, and other similar pre-coloring based on the graph spectrum, like the Fürer spectral invariant, are strictly less expressive than 2-WL.

// TODO: example: Shrikhande graph vs the 4×4 Rook’s graph or the one in the paper

The spectral pre-coloring in practice can be used to improve the expressive power of message passing neural networks. The coloring is computed before the learning phase and such colors are appended to the already existing features of each node. This coloring is especially useful because an approximation of the heat kernel can be computed efficiently even for large graphs by using only some of the smallest eigenvalues and the corresponding eigenvectors@feldman2022weisfeilerlemaninfinitespectral. Since the objective is to distinguish between different nodes, and not to have an exact value of the heat kernel, this approximation is sufficient in practice as shown by Feldman et al.@feldman2022weisfeilerlemaninfinitespectral.


= Conclusion

In this work, we characterized the graph isomorphism problem, emphasizing its unique role within computational complexity theory. We then examined the Weisfeiler-Lehman (WL) algorithm, a powerful method for testing graph isomorphism through the iterative refinement of vertex colorings based on neighborhood information. Both the one-dimensional (1-WL) and the k-dimensional (k-WL) versions were analyzed, highlighting their expressive power.

We also introduced spectral graph theory, focusing on the Laplacian matrix of a graph and its spectrum, and discussed how spectral information encodes structural properties of a graph.

Building on these theoretical foundations, we analyzed the study by Feldman et al. @feldman2022weisfeilerlemaninfinitespectral, which demonstrates that spectrum-based pre-coloring enhances the expressiveness of 1-WL, resulting in the Spectral WL method. The theoretical results show that permutation-equivariant pre-colorings can indefinitely improve the expressive power of 1-WL, with spectral pre-coloring being more expressive than the standard 1-WL while remaining computationally efficient.

Overall, these findings point to Spectral WL as a promising approach for practical graph isomorphism testing and related applications, particularly in the context of graph neural networks.

#pagebreak()
