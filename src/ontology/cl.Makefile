## Customize Makefile settings for cl
## 
## If you need to customize your Makefile, make
## changes here rather than in the main Makefile
# railing-whitespace  xref-syntax

#mirror/pr.owl: mirror/pr.trigger
#	@if [ $(MIR) = true ] && [ $(IMP) = true ]; then $(ROBOT) convert -I $(URIBASE)/pr.owl -o $@.tmp.owl && mv $@.tmp.owl $@; fi
#	echo "skipped PR mirror"

#imports/pr_import.owl:
#	echo "skipped pr import"

#tmp/clo_logical.owl: mirror/clo.owl
#	echo "Skipped clo logical" && cp $< $@
	
#tmp/ncbitaxon_logical.owl: mirror/ncbitaxon.owl
#	echo "Skipped clo logical" && touch $@

#tmp/pr_logical.owl: mirror/pr.owl
#	echo "Skipped pr logical" && cp $< $@
	
#tmp/chebi_logical.owl: mirror/chebi.owl
#	echo "Skipped chebi logical" && cp $< $@

#mirror/ncbitaxon.owl:
#	echo "STRONG WARNING: skipped ncbitaxon mirror!"

#imports/ncbitaxon_import.owl:
#	echo "STRONG WARNING: skipped ncbitaxon import!"

object_properties.txt: $(SRC)
	$(ROBOT) query --use-graphs true -f csv -i $< --query ../sparql/object-properties-in-signature.sparql $@

non_native_classes.txt: $(SRC)
	$(ROBOT) query --use-graphs true -f csv -i $< --query ../sparql/non-native-classes.sparql $@.tmp &&\
	cat $@.tmp | sort | uniq >  $@
	rm -f $@.tmp

# TODO add back: 		remove --term-file non_native_classes.txt \


#$(ONT).obo: $(ONT)-basic.owl
#	$(ROBOT) convert --input $< --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@.tmp.obo && grep -v ^owl-axioms $@.tmp.obo > $@ && rm $@.tmp.obo

#$(PATTERNDIR)/dosdp-patterns: .FORCE
#	echo "WARNING WARNING Skipped until fixed: delete from cl.Makefile"

#####################################################################################
### Run ontology-release-runner instead of ROBOT as long as ROBOT is broken.      ###
#####################################################################################

# The reason command (and the reduce command) removed some of the very crucial asserted axioms at this point.
# That is why we first need to extract all logical axioms (i.e. subsumptions) and merge them back in after 
# The reasoning step is completed. This will be a big problem when we switch to ROBOT completely..

tmp/cl_terms.txt: $(SRC)
	$(ROBOT) query --use-graphs true -f csv -i $< --query ../sparql/cl_terms.sparql $@

tmp/asserted-subclass-of-axioms.obo: $(SRC) tmp/cl_terms.txt
	$(ROBOT) merge --input $< \
		filter --term-file tmp/cl_terms.txt --axioms "logical" --preserve-structure false \
		convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@.tmp.obo && mv $@.tmp.obo $@

# All this terrible OBO file hacking is necessary to make sure downstream tools can actually compile something resembling valid OBO (oort!).
#http://purl.obolibrary.org/obo/UBERON_0004370 EquivalentTo basement membrane needs fixing
# Removing drains CARO relationship is a necessary hack because of an OBO bug that turns universals
# into existentials on roundtrip

tmp/source-merged.obo: $(SRC) tmp/asserted-subclass-of-axioms.obo
	$(ROBOT) merge --input $< \
		reason --reasoner ELK \
		relax \
		remove --axioms equivalent \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o tmp/source-merged.owl.obo &&\
		grep -v ^owl-axioms tmp/source-merged.owl.obo > tmp/source-stripped2.obo &&\
		grep -v '^def[:][ ]["]x[ ]only[ ]in[ ]taxon' tmp/source-stripped2.obo > tmp/source-stripped3.obo &&\
		grep -v '^relationship[:][ ]drains[ ]CARO' tmp/source-stripped3.obo > tmp/source-stripped.obo &&\
		cat tmp/source-stripped.obo | perl -0777 -e '$$_ = <>; s/name[:].*\nname[:]/name:/g; print' | perl -0777 -e '$$_ = <>; s/range[:].*\nrange[:]/range:/g; print' | perl -0777 -e '$$_ = <>; s/domain[:].*\ndomain[:]/domain:/g; print' | perl -0777 -e '$$_ = <>; s/comment[:].*\ncomment[:]/comment:/g; print' | perl -0777 -e '$$_ = <>; s/created_by[:].*\ncreated_by[:]/created_by:/g; print' | perl -0777 -e '$$_ = <>; s/def[:].*\ndef[:]/def:/g; print' > $@ &&\
		rm tmp/source-merged.owl.obo tmp/source-stripped.obo tmp/source-stripped2.obo tmp/source-stripped3.obo

oort: tmp/source-merged.obo
	ontology-release-runner --reasoner elk $< --no-subsets --skip-ontology-checks --allow-equivalent-pairs --simple --relaxed --asserted --allow-overwrite --outdir oort

tmp/$(ONT)-stripped.owl: oort
	$(ROBOT) filter --input oort/$(ONT)-simple.owl --term-file tmp/cl_terms.txt --trim false \
		convert -o $@

# cl_signature.txt should contain all CL terms and all properties (and subsets) used by the ontology.
# It serves like a proper signature, but including annotation properties
tmp/cl_signature.txt: tmp/$(ONT)-stripped.owl tmp/cl_terms.txt
	$(ROBOT) query -f csv -i $< --query ../sparql/object-properties.sparql $@_prop.tmp &&\
	cat tmp/cl_terms.txt $@_prop.tmp | sort | uniq > $@ &&\
	rm $@_prop.tmp

# The standard simple artefacts keeps a bunch of irrelevant Typedefs which are a result of the merge. The following steps takes the result
# of the oort simple version, and then removes them. A second problem is that oort does not deal well with cycles and removes some of the 
# asserted CL subsumptions. This can hopefully be solved once we can move all the way to ROBOT, but for now, it requires merging in
# the asserted hierarchy and reducing again.


# Note that right now, TypeDefs that are CL native (like has_age) are included in the release!

$(ONT)-simple.owl: tmp/cl_signature.txt oort
	echo "WARNING: $@ is not generated with the default ODK specification."
	$(ROBOT) merge --input oort/$(ONT)-simple.owl \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		reduce \
		remove --term-file tmp/cl_signature.txt --select complement --trim false \
		convert -o $@

$(ONT)-simple.obo: tmp/cl_signature.txt oort
	echo "WARNING: $@ is not generated with the default ODK specification."
	$(ROBOT) merge --input oort/$(ONT)-simple.obo \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		reduce \
		remove --term-file tmp/cl_signature.txt --select complement --trim false \
		convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@.tmp.obo &&\
		grep -v ^owl-axioms $@.tmp.obo > $@.tmp &&\
		cat $@.tmp | perl -0777 -e '$$_ = <>; s/name[:].*\nname[:]/name:/g; print' | perl -0777 -e '$$_ = <>; s/def[:].*\nname[:]/def:/g; print' > $@
		rm -f $@.tmp.obo $@.tmp
		
$(ONT)-basic.owl: tmp/cl_signature.txt oort
	echo "WARNING: $@ is not generated with the default ODK specification."
	$(ROBOT) merge --input oort/$(ONT)-simple.owl \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		reduce \
		remove --term-file tmp/cl_signature.txt --select complement --trim false \
		remove --term-file keeprelations.txt --select complement --select object-properties --trim true \
		remove --axioms disjoint --trim false \
		convert -o $@
		

#$(ONT)-hipc.owl: $(ONT).owl ../templates/mouse_specific_groupings.owl ../templates/human_specific_groupings.owl
#	$(ROBOT) merge $(patsubst %, -i %, $^) \
#		reason \
#		relax \
#		reduce \
#		convert -o $@

#$(RELEASEDIR)/views:
#	mkdir -p $@

#release_views: $(ONT)-hipc.owl | $(RELEASEDIR)/views
#	rsync -R $^ $(RELEASEDIR)/views
	
# prepare_release: release_views

#diff_basic: $(ONT)-basic2.owl $(ONT)-basic3.owl
#	$(ROBOT) diff --left cl-basic2.owl --right cl-basic3.owl -o tmp/diffrel.txt

$(ONT)-basic.obo: tmp/cl_signature.txt oort
	echo "WARNING: $@ is not generated with the default ODK specification."
	$(ROBOT) merge --input oort/$(ONT)-simple.obo \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		reduce \
		remove --term-file tmp/cl_signature.txt --select complement --trim false \
		remove --term-file keeprelations.txt --select complement --select object-properties --trim true \
		remove --axioms disjoint --trim false \
		convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@.tmp.obo &&\
		grep -v ^owl-axioms $@.tmp.obo > $@.tmp &&\
		cat $@.tmp | perl -0777 -e '$$_ = <>; s/name[:].*\nname[:]/name:/g; print' | perl -0777 -e '$$_ = <>; s/def[:].*\nname[:]/def:/g; print' > $@
		rm -f $@.tmp.obo $@.tmp


#fail_seed_by_entity_type_cl:
#	robot query --use-graphs false -f csv -i cl-edit.owl --query ../sparql/object-properties.sparql $@.tmp &&\
#	cat $@.tmp | sort | uniq >  $@.txt && rm -f $@.tmp 

#works_seed_by_entity_type_cl:
#	robot query --use-graphs false -f csv -i cl-edit.owl --query ../sparql/object-properties-in-signature.sparql $@.tmp &&\
#	cat $@.tmp | sort | uniq >  $@.txt && rm -f $@.tmp 

	
##############################################
##### CL Template pipeline ###################
##############################################

TEMPLATESDIR=../templates
DEPENDENCY_TEMPLATE=dependencies.tsv
TEMPLATES=$(filter-out $(DEPENDENCY_TEMPLATE), $(notdir $(wildcard $(TEMPLATESDIR)/*.tsv)))
TEMPLATES_OWL=$(patsubst %.tsv, $(TEMPLATESDIR)/%.owl, $(TEMPLATES))
TEMPLATES_TSV=$(patsubst %.tsv, $(TEMPLATESDIR)/%.tsv, $(TEMPLATES))

p:
	echo $(TEMPLATES)
	echo $(TEMPLATES_TSV)
	echo $(TEMPLATES_OWL)

templates: prepare_templates $(TEMPLATES_OWL)

remove_template_classes_from_edit.txt: $(TEMPLATES_TSV)
	for f in $^; do \
			cut -f1 $${f} >> tmp.txt; \
			cat tmp.txt | grep 'CL:' | sort | uniq > $@; \
	done \
	rm tmp.txt

remove_template_classes_from_edit: remove_template_classes_from_edit.txt $(SRC)
	$(ROBOT) remove -i $(SRC) -T $< --preserve-structure false -o $(SRC).ofn && mv $(SRC).ofn $(SRC)

prepare_templates: ../templates/config.txt
	sh ../scripts/download_templates.sh $<

#components/all_templates.owl: $(TEMPLATES_OWL)
#	$(ROBOT) merge $(patsubst %, -i %, $^) \
#		annotate --ontology-iri $(ONTBASE)/$@ --version-iri $(ONTBASE)/releases/$(TODAY)/$@ \
#		--output $@.tmp.owl && mv $@.tmp.owl $@

$(TEMPLATESDIR)/dependencies.owl: $(TEMPLATESDIR)/dependencies.tsv
	$(ROBOT) merge -i $(SRC) template --template $< --prefix "CP: http://purl.obolibrary.org/obo/CP_" --output $@ && \
	$(ROBOT) annotate --input $@ --ontology-iri $(ONTBASE)/components/$*.owl -o $@

$(TEMPLATESDIR)/%.owl: $(TEMPLATESDIR)/%.tsv $(SRC) $(TEMPLATESDIR)/dependencies.owl
	$(ROBOT) merge -i $(SRC) -i $(TEMPLATESDIR)/dependencies.owl template --template $< --output $@ && \
	$(ROBOT) annotate --input $@ --ontology-iri $(ONTBASE)/components/$*.owl -o $@

CL_EDIT_GITHUB_MASTER=https://raw.githubusercontent.com/obophenotype/cell-ontology/master/src/ontology/cl-edit.owl

tmp/src-noimports.owl: $(SRC)
	$(ROBOT) remove -i $< --select imports -o $@

tmp/src-imports.owl: $(SRC)
	$(ROBOT) merge -i $< -o $@
	
tmp/src-master-noimports.owl:
	$(ROBOT) remove -I $(CL_EDIT_GITHUB_MASTER) --select imports -o $@
	
tmp/src-master-imports.owl:
	$(ROBOT) merge -I $(CL_EDIT_GITHUB_MASTER) -o $@

reports/diff_edit_%.md: tmp/src-master-%.owl tmp/src-%.owl
	$(ROBOT) diff --left tmp/src-master-$*.owl --right tmp/src-$*.owl -f markdown -o $@

reports/diff_edit_%.txt: tmp/src-master-%.owl tmp/src-%.owl
	$(ROBOT) diff --left tmp/src-master-$*.owl --right tmp/src-$*.owl -o $@

branch_diffs: reports/diff_edit_imports.md reports/diff_edit_noimports.md reports/diff_edit_imports.txt reports/diff_edit_noimports.txt

tmp/cl-current.owl: $(ONT).owl
	$(ROBOT) remove -i $< --term rdfs:label --select complement --select annotation-properties \
		remove --base-iri $(URIBASE)/CL_ --axioms external -o $@

tmp/cl-lastbuild.owl: .FORCE
	$(ROBOT) remove -I $(URIBASE)/$(ONT).owl --term rdfs:label --select complement --select annotation-properties \
		remove --base-iri $(URIBASE)/CL_ --axioms external -o $@

reports/obo-diff.txt: tmp/cl-lastbuild.owl tmp/cl-current.owl
	$(ROBOT) diff --left $< --right tmp/cl-current.owl -f markdown -o $@
	#perl ../scripts/obo-simple-diff.pl $^ > $@.tmp && mv $@.tmp $@
	
all_reports: reports/obo-diff.txt


normalise_xsd_string: $(SRC)
	sed -i -E "s/Annotation[(](oboInOwl[:]hasDbXref [\"][^\"]*[\"])[)]/Annotation(\1^^xsd:string)/" $<
