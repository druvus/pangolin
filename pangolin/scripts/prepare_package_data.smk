import csv
from Bio import SeqIO
import codecs

# requires metadata and fasta file in config

rule all:
    input:
        config["outdir"] + "/anonymised.aln.fasta.treefile",
        config["outdir"] + "/anonymised.encrypted.aln.fasta"

rule extract_representative_sequences:
    input:
        metadata = config["metadata"],
        fasta = config["fasta"]
    output:
        config["outdir"] + "/representative_sequences.fasta"
    run:
        tax_dict = {}
        with open(input.metadata,"rb") as f:
            for l in f:
                l = l.decode("utf-8","ignore").rstrip()
                if not l.startswith("name"):
                    tokens = l.split(",")
                    if tokens[-1] =="1":
                        tax_dict[tokens[0]]= tokens[1]
                        
        fw = open(output[0], "w")
        c = 0
        for record in SeqIO.parse(input.fasta,"fasta"):
            if record.id in tax_dict:
                c+=1
                record_list = record.id.split('|')
                record_list[2] = tax_dict[record.id]
                new_id = '|'.join(record_list)
                fw.write(f">{new_id}\n{record.seq}\n")
        print(f"{c} representative sequences written to {output[0]}")
        fw.close()

rule mafft_representative_sequences:
    input:
        rules.extract_representative_sequences.output
    output:
        config["outdir"] + "/representative_sequences.aln.fasta"
    shell:
        "mafft {input[0]:q} > {output[0]:q}"

rule anonymise_headers:
    input:
        rules.mafft_representative_sequences.output
    output:
        fasta = config["outdir"] + "/anonymised.aln.fasta",
        key = config["outdir"] + "tax_key.csv"
    run:
        fkey = open(output.key, "w")
        fkey.write("taxon,key\n")
        key_dict = {}
        c = 0
        with open(output.fasta, "w") as fw:
            for record in SeqIO.parse(input[0],"fasta"):
                c+=1
                record_list = record.id.split('|')
                lineage = record_list[2]
                new_id = ""
                if "EPI_ISL_406801" in record.id: # this is the WH04 GISAID ID
                    print(record.id)
                    new_id = f"outgroup_A"
                else:
                    new_id = f"{c}_{lineage}"

                fkey.write(f"{record.id},{new_id}\n")
                fw.write(f">{new_id}\n{record.seq}\n")
            
            print(f"{c+1} anonymised sequences written to {output.fasta}")
        fkey.close()

rule encrypt_fasta:
    input:
        rules.anonymise_headers.output.fasta
    output:
        config["outdir"] + "/anonymised.encrypted.aln.fasta"
    run:
        c = 0
        with open(output[0],"w") as fw:
            for record in SeqIO.parse(input[0],"fasta"):
                encrypted_seq = codecs.encode(str(record.seq), 'rot_13')
                fw.write(f">{record.id}\n{encrypted_seq}\n")
                c+=1
        print(f"Encrypted {c} sequences with rot13")

rule iqtree_representative_sequences:
    input:
        rules.anonymise_headers.output.fasta
    output:
        config["outdir"] + "/anonymised.aln.fasta.treefile"
    shell:
        "iqtree -s {input[0]:q} -bb 1000 -m HKY -o 'outgroup_A'"
