# julia ts
using JSON

using LightGraphs, MetaGraphs
using GraphIO
using GraphPlot
using Compose
#using Cairo, Fontconfig

function list_jl_files(path)
    jl_files = []
    for (root, dirs, files) in walkdir(path)
        only_jl = filter(x -> occursin(".jl", x), files)
        jl_files = vcat(jl_files, [root * "/" * file_name for file_name in only_jl])
    end
    return jl_files
end

function only_struct(e::Expr)
    if in(e.head, [:struct, :abstract, :primitive]) 
        push!(li_struct, e)
    else
        for arg in e.args
            if typeof(arg) == Expr
                only_struct(arg)
            end
        end
    end
end

function parse(file_path)
    all_lines = readlines(file_path)
    lines = reduce((x, y) -> x * "\n" * y, all_lines)
    
    try
        file_expr = Meta.parse("begin $lines end")
        only_struct(file_expr)
    catch 
        println("File $file_path not parsed...")
    end
end

function convert_dependance(dependance::Expr)
    name = dependance.args[1]
    dependsof = dependance.args[2]
    if dependance.head == :curly
        return name, :no
    end
    if typeof(name) == Expr
        if name.head == :curly
            name = name.args[1]
            if typeof(name) == Expr
                return :no, :no
            end
        elseif name.head == :$
            return :no, :no
        end
    end

    if typeof(dependsof) == Expr
        if dependsof.head == :curly
            return name, dependsof.args[1]
        elseif dependsof.head == :$
            return :no, :no            
        elseif length(dependsof.args) == 2
            return name, dependsof.args[2]
        else
            return :no, :no           
        end 
    end
    return name, dependsof
end

function build_dictionnary(stru::Expr)
    if in(stru.head, [:abstract, :primitive])
        dependance = stru.args[1]
    else
        dependance = stru.args[2]
    end

    if typeof(dependance) == Expr
        name, dependsof = convert_dependance(dependance)
        if name == dependsof == :no
            return 
        elseif dependsof == :no
            #if !haskey(all_references, name)
            #    all_references[name] = []
            #end
            return             
        elseif haskey(all_references, dependsof)
            push!(all_references[dependsof], name)
        else
            all_references[dependsof] = Symbol[name]
        end
    #elseif !haskey(all_references, dependance)
    #    all_references[dependance] = [] 
    end
end



function build_graph(refs)
    graph = MetaDiGraph(SimpleDiGraph())

    for k in keys(refs)
        add_vertex!(graph, :name, k)
    end

    for (from, list_togo) in refs
        for to in list_togo
            id1 = collect(filter_vertices(graph, :name, from))[1]
            id2 = collect(filter_vertices(graph, :name, to))
            if length(id2) == 0
                add_vertex!(graph, :name, to)
                id2 = collect(filter_vertices(graph, :name, to))[1]
            else
                id2 = id2[1]
            end
            add_edge!(graph, id1, id2)
        end
    end
    return graph
end


julia_path = "PATH"

if isfile("all_reference.json")
    all_references = readlines(open("all_reference.json", "r"))

    all_references = JSON.parse(reduce(*, all_references))
else
    println("Build list of files...")
    jl_files = list_jl_files(julia_path)
    li_struct = Expr[]
    println("Parsing files...")
    map(parse, jl_files)
    #only_names = map(stru -> stru.args[2].args[1], li_struct)
    all_references = Dict()
    println("Building dictionnary...")
    map(build_dictionnary, li_struct)   
    write(open("all_reference.json", "w"), JSON.json(all_references, 1))
end

function name_ancestor(subgraph)
    #println(outneighbors(subgraph, 1), " ", inneighbors(subgraph, 1))
    ancestor = filter(node -> length(inneighbors(subgraph, node)) == 0, vertices(subgraph))
    id_ancestor = collect(ancestor)[1]
    return get_prop(subgraph, id_ancestor, :name)
end

println("Build graph...")
graph = build_graph(all_references)

println("Plot & Save")
for nodelist in weakly_connected_components(graph)
    subgraph, vmap = induced_subgraph(graph, nodelist)
    #layout=(args...)->spring_layout(args...; C=20)
    labels = [get_prop(subgraph, v, :name) for v in vertices(subgraph)]
    plot = gplot(subgraph, layout=spring_layout, nodelabel=labels)
    #draw(SVG("JuliaTS_" * name_ancestor(subgraph) * ".svg", 16cm, 16cm), plot)
    draw(PNG("JuliaTS_" * name_ancestor(subgraph) * ".png", 16cm, 16cm), plot)
end
