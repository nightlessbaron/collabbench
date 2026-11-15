#!/bin/bash
set -euo pipefail
cd "${WORKSPACE:-/workspace}"
git apply --whitespace=nowarn <<'COLLAB_REFERENCE_PATCH_EOF'
diff --git a/emmet-api/emmet/api/core/settings.py b/emmet-api/emmet/api/core/settings.py
index 27ad671..f7766a6 100644
--- a/emmet-api/emmet/api/core/settings.py
+++ b/emmet-api/emmet/api/core/settings.py
@@ -1,7 +1,8 @@
-from typing import Literal
-from pydantic import BaseSettings, Field
+from typing import Literal, Optional
+from pydantic import Field
 from emmet.api import __file__ as root_dir
 import os
+from pydantic_settings import BaseSettings, SettingsConfigDict
 
 
 class MAPISettings(BaseSettings):
@@ -19,7 +20,7 @@ class MAPISettings(BaseSettings):
 
     DB_VERSION: str = Field("2021.11.10", description="Database version")
 
-    DB_NAME_SUFFIX: Literal["blue", "green"] = Field(
+    DB_NAME_SUFFIX: Optional[Literal["blue", "green"]] = Field(
         None, description="Database name suffix. Either blue or green."
     )
 
@@ -27,6 +28,4 @@ class MAPISettings(BaseSettings):
         30,
         description="Number of seconds to wait for pymongo operations before raising a timeout error.",
     )
-
-    class Config:
-        env_prefix = "MAPI_"
+    model_config = SettingsConfigDict(env_prefix="MAPI_", extra="ignore")
diff --git a/emmet-api/emmet/api/routes/materials/summary/query_operators.py b/emmet-api/emmet/api/routes/materials/summary/query_operators.py
index 403bbc1..50672d7 100644
--- a/emmet-api/emmet/api/routes/materials/summary/query_operators.py
+++ b/emmet-api/emmet/api/routes/materials/summary/query_operators.py
@@ -1,5 +1,5 @@
 from sys import version_info
-from typing import Optional
+from typing import Optional, get_args
 from fastapi import Query
 
 from maggma.api.query_operator import QueryOperator
@@ -207,7 +207,11 @@ class SearchStatsQuery(QueryOperator):
 
     def __init__(self, search_doc):
         valid_numeric_fields = tuple(
-            sorted(k for k, v in search_doc.__fields__.items() if v.type_ == float)
+            sorted(
+                k
+                for k, v in search_doc.model_fields.items()
+                if float in get_args(v.annotation)
+            )
         )
 
         def query(
diff --git a/emmet-builders/emmet/builders/abinit/phonon.py b/emmet-builders/emmet/builders/abinit/phonon.py
index fb00f01..9be05d7 100644
--- a/emmet-builders/emmet/builders/abinit/phonon.py
+++ b/emmet-builders/emmet/builders/abinit/phonon.py
@@ -278,12 +278,12 @@ class PhononBuilder(Builder):
             self.logger.debug("Item generated for {}".format(item["mp_id"]))
 
             d = dict(
-                abiph=jsanitize(ap.dict(), allow_bson=True),
-                phbs=jsanitize(phbs.dict(), allow_bson=True),
-                phws=jsanitize(phws.dict(), allow_bson=True),
-                phdos=jsanitize(phdos.dict(), allow_bson=True),
-                ddb=jsanitize(ddb.dict(), allow_bson=True),
-                th_disp=jsanitize(th_disp.dict(), allow_bson=True),
+                abiph=jsanitize(ap.model_dump(), allow_bson=True),
+                phbs=jsanitize(phbs.model_dump(), allow_bson=True),
+                phws=jsanitize(phws.model_dump(), allow_bson=True),
+                phdos=jsanitize(phdos.model_dump(), allow_bson=True),
+                ddb=jsanitize(ddb.model_dump(), allow_bson=True),
+                th_disp=jsanitize(th_disp.model_dump(), allow_bson=True),
             )
 
             return d
diff --git a/emmet-builders/emmet/builders/abinit/sound_velocity.py b/emmet-builders/emmet/builders/abinit/sound_velocity.py
index 29a4e54..669fedf 100644
--- a/emmet-builders/emmet/builders/abinit/sound_velocity.py
+++ b/emmet-builders/emmet/builders/abinit/sound_velocity.py
@@ -63,7 +63,9 @@ class SoundVelocityBuilder(Builder):
         # All relevant materials that have been updated since phonon props were last calculated
         q = dict(self.query)
 
-        mats = self.phonon.newer_in(self.phonon_materials, exhaustive=True, criteria=q)
+        mats = self.sound_vel.newer_in(
+            self.phonon_materials, exhaustive=True, criteria=q
+        )
 
         N = ceil(len(mats) / number_splits)
 
@@ -141,7 +143,7 @@ class SoundVelocityBuilder(Builder):
 
             self.logger.debug("Item generated for {}".format(item["mp_id"]))
 
-            return jsanitize(sv.dict())
+            return jsanitize(sv.model_dump())
         except Exception:
             self.logger.warning(
                 "Error generating the sound velocity for {}: {}".format(
diff --git a/emmet-builders/emmet/builders/feff/xas.py b/emmet-builders/emmet/builders/feff/xas.py
index b8346ac..7b640b2 100644
--- a/emmet-builders/emmet/builders/feff/xas.py
+++ b/emmet-builders/emmet/builders/feff/xas.py
@@ -37,7 +37,7 @@ class XASBuilder(GroupBuilder):
 
         try:
             docs = XASDoc.from_task_docs(tasks, material_id=mpid)
-            processed = [d.dict() for d in docs]
+            processed = [d.model_dump() for d in docs]
 
             for d in processed:
                 d.update({"state": "successful"})
diff --git a/emmet-builders/emmet/builders/materials/absorption_spectrum.py b/emmet-builders/emmet/builders/materials/absorption_spectrum.py
index 9af9271..612cab4 100644
--- a/emmet-builders/emmet/builders/materials/absorption_spectrum.py
+++ b/emmet-builders/emmet/builders/materials/absorption_spectrum.py
@@ -99,7 +99,7 @@ class AbsorptionBuilder(Builder):
             origins=[origin_entry],
         )
 
-        return jsanitize(doc.dict(), allow_bson=True)
+        return jsanitize(doc.model_dump(), allow_bson=True)
 
     def update_targets(self, items):
         """
diff --git a/emmet-builders/emmet/builders/materials/bonds.py b/emmet-builders/emmet/builders/materials/bonds.py
index 1224ead..5dc75dc 100644
--- a/emmet-builders/emmet/builders/materials/bonds.py
+++ b/emmet-builders/emmet/builders/materials/bonds.py
@@ -50,6 +50,6 @@ class BondingBuilder(MapBuilder):
         bonding_doc = BondingDoc.from_structure(
             structure=structure, material_id=mpid, deprecated=deprecated
         )
-        doc = jsanitize(bonding_doc.dict(), allow_bson=True)
+        doc = jsanitize(bonding_doc.model_dump(), allow_bson=True)
 
         return doc
diff --git a/emmet-builders/emmet/builders/materials/chemenv.py b/emmet-builders/emmet/builders/materials/chemenv.py
index 676e938..617dda2 100644
--- a/emmet-builders/emmet/builders/materials/chemenv.py
+++ b/emmet-builders/emmet/builders/materials/chemenv.py
@@ -41,4 +41,4 @@ class ChemEnvBuilder(MapBuilder):
             deprecated=deprecated,
         )
 
-        return jsanitize(doc.dict(), allow_bson=True)
+        return jsanitize(doc.model_dump(), allow_bson=True)
diff --git a/emmet-builders/emmet/builders/materials/corrected_entries.py b/emmet-builders/emmet/builders/materials/corrected_entries.py
index 7a4d650..6834a9d 100644
--- a/emmet-builders/emmet/builders/materials/corrected_entries.py
+++ b/emmet-builders/emmet/builders/materials/corrected_entries.py
@@ -194,7 +194,7 @@ class CorrectedEntriesBuilder(Builder):
 
         doc = CorrectedEntriesDoc(chemsys=chemsys, entries=corrected_entries)
 
-        return jsanitize(doc.dict(), allow_bson=True)
+        return jsanitize(doc.model_dump(), allow_bson=True)
 
     def update_targets(self, items):
         """
diff --git a/emmet-builders/emmet/builders/materials/dielectric.py b/emmet-builders/emmet/builders/materials/dielectric.py
index 9c4b1d7..d907350 100644
--- a/emmet-builders/emmet/builders/materials/dielectric.py
+++ b/emmet-builders/emmet/builders/materials/dielectric.py
@@ -99,7 +99,7 @@ class DielectricBuilder(Builder):
             last_updated=item["updated_on"],
         )
 
-        return jsanitize(doc.dict(), allow_bson=True)
+        return jsanitize(doc.model_dump(), allow_bson=True)
 
     def update_targets(self, items):
         """
diff --git a/emmet-builders/emmet/builders/materials/elasticity.py b/emmet-builders/emmet/builders/materials/elasticity.py
index 09c2b75..fe094ac 100644
--- a/emmet-builders/emmet/builders/materials/elasticity.py
+++ b/emmet-builders/emmet/builders/materials/elasticity.py
@@ -217,7 +217,7 @@ class ElasticityBuilder(Builder):
             optimization_dir_name=final_opt["dir_name"],
             fitting_method="finite_difference",
         )
-        elasticity_doc = jsanitize(elasticity_doc.dict(), allow_bson=True)
+        elasticity_doc = jsanitize(elasticity_doc.model_dump(), allow_bson=True)
 
         return elasticity_doc
 
diff --git a/emmet-builders/emmet/builders/materials/electrodes.py b/emmet-builders/emmet/builders/materials/electrodes.py
index 463349c..effa51b 100644
--- a/emmet-builders/emmet/builders/materials/electrodes.py
+++ b/emmet-builders/emmet/builders/materials/electrodes.py
@@ -307,7 +307,7 @@ class StructureGroupBuilder(Builder):
             stol=self.stol,
             angle_tol=self.angle_tol,
         )
-        return [sg.dict() for sg in s_groups]
+        return [sg.model_dump() for sg in s_groups]
 
     def _remove_targets(self, rm_ids):
         self.sgroups.remove_docs({"material_ids": {"$in": rm_ids}})
@@ -458,7 +458,7 @@ class InsertionElectrodeBuilder(Builder):
         if ie is None:
             return None  # type: ignore
             # {"failed_reason": "unable to create InsertionElectrode document"}
-        return jsanitize(ie.dict())
+        return jsanitize(ie.model_dump())
 
     def update_targets(self, items: List):
         items = list(filter(None, items))
@@ -590,7 +590,7 @@ class ConversionElectrodeBuilder(Builder):
                     comps.add(c)
                     unique_reaction_compositions.add(c)
                 reaction_compositions.append(comps)
-                new_docs.append(jsanitize(conversion_electrode_doc.dict()))
+                new_docs.append(jsanitize(conversion_electrode_doc.model_dump()))
 
         entry_id_mapping = {}
         for c in unique_reaction_compositions:
diff --git a/emmet-builders/emmet/builders/materials/electronic_structure.py b/emmet-builders/emmet/builders/materials/electronic_structure.py
index cfa496a..a565706 100644
--- a/emmet-builders/emmet/builders/materials/electronic_structure.py
+++ b/emmet-builders/emmet/builders/materials/electronic_structure.py
@@ -262,7 +262,7 @@ class ElectronicStructureBuilder(Builder):
             )
 
         if doc.dos is not None:
-            dos_dict = doc.dos.dict()
+            dos_dict = doc.dos.model_dump()
             mag_orderings.update(
                 {dos_dict["total"][Spin.up]["task_id"]: dos_dict["magnetic_ordering"]}
             )
@@ -290,7 +290,7 @@ class ElectronicStructureBuilder(Builder):
                     f"{bs_entry['task_id']}). A correction calculation is planned."
                 )
 
-        return doc.dict()
+        return doc.model_dump()
 
     def update_targets(self, items):
         """
diff --git a/emmet-builders/emmet/builders/materials/magnetism.py b/emmet-builders/emmet/builders/materials/magnetism.py
index c640de1..22946fc 100644
--- a/emmet-builders/emmet/builders/materials/magnetism.py
+++ b/emmet-builders/emmet/builders/materials/magnetism.py
@@ -109,7 +109,7 @@ class MagneticBuilder(Builder):
             last_updated=item["last_updated"],
         )
 
-        return jsanitize(doc.dict(), allow_bson=True)
+        return jsanitize(doc.model_dump(), allow_bson=True)
 
     def update_targets(self, items):
         """
diff --git a/emmet-builders/emmet/builders/materials/optimade.py b/emmet-builders/emmet/builders/materials/optimade.py
index 3e4337e..baafdab 100644
--- a/emmet-builders/emmet/builders/materials/optimade.py
+++ b/emmet-builders/emmet/builders/materials/optimade.py
@@ -112,7 +112,7 @@ class OptimadeMaterialsBuilder(Builder):
             thermo_calcs=thermo_calcs,
         )
 
-        doc = jsanitize(optimade_doc.dict(), allow_bson=True)
+        doc = jsanitize(optimade_doc.model_dump(), allow_bson=True)
 
         return doc
 
diff --git a/emmet-builders/emmet/builders/materials/oxidation_states.py b/emmet-builders/emmet/builders/materials/oxidation_states.py
index 954e984..0f82646 100644
--- a/emmet-builders/emmet/builders/materials/oxidation_states.py
+++ b/emmet-builders/emmet/builders/materials/oxidation_states.py
@@ -46,6 +46,6 @@ class OxidationStatesBuilder(MapBuilder):
         oxi_doc = OxidationStateDoc.from_structure(
             structure=structure, material_id=mpid, deprecated=deprecated
         )
-        doc = jsanitize(oxi_doc.dict(), allow_bson=True)
+        doc = jsanitize(oxi_doc.model_dump(), allow_bson=True)
 
         return doc
diff --git a/emmet-builders/emmet/builders/materials/piezoelectric.py b/emmet-builders/emmet/builders/materials/piezoelectric.py
index 821e7d7..31d0d6a 100644
--- a/emmet-builders/emmet/builders/materials/piezoelectric.py
+++ b/emmet-builders/emmet/builders/materials/piezoelectric.py
@@ -146,7 +146,7 @@ class PiezoelectricBuilder(Builder):
             last_updated=item["updated_on"],
         )
 
-        return jsanitize(doc.dict(), allow_bson=True)
+        return jsanitize(doc.model_dump(), allow_bson=True)
 
     def update_targets(self, items):
         """
diff --git a/emmet-builders/emmet/builders/materials/robocrys.py b/emmet-builders/emmet/builders/materials/robocrys.py
index 7d1d402..8fca4b1 100644
--- a/emmet-builders/emmet/builders/materials/robocrys.py
+++ b/emmet-builders/emmet/builders/materials/robocrys.py
@@ -42,4 +42,4 @@ class RobocrystallographerBuilder(MapBuilder):
             fields=[],
         )
 
-        return jsanitize(doc.dict(), allow_bson=True)
+        return jsanitize(doc.model_dump(), allow_bson=True)
diff --git a/emmet-builders/emmet/builders/materials/substrates.py b/emmet-builders/emmet/builders/materials/substrates.py
index 6f7e3a9..a6be142 100644
--- a/emmet-builders/emmet/builders/materials/substrates.py
+++ b/emmet-builders/emmet/builders/materials/substrates.py
@@ -127,7 +127,7 @@ class SubstratesBuilder(Builder):
             last_updated=item["last_updated"],
         )
 
-        return jsanitize(substrate_doc.dict(), allow_bson=True)
+        return jsanitize(substrate_doc.model_dump(), allow_bson=True)
 
     def update_targets(self, items):
         """
diff --git a/emmet-builders/emmet/builders/materials/thermo.py b/emmet-builders/emmet/builders/materials/thermo.py
index d54fe93..97dee14 100644
--- a/emmet-builders/emmet/builders/materials/thermo.py
+++ b/emmet-builders/emmet/builders/materials/thermo.py
@@ -198,12 +198,12 @@ class ThermoBuilder(Builder):
                         thermo_type=thermo_type,
                     )
 
-                    pd_data = jsanitize(pd_doc.dict(), allow_bson=True)
+                    pd_data = jsanitize(pd_doc.model_dump(), allow_bson=True)
 
                     pd_docs = [pd_data]
 
             docs_pd_pair = (
-                jsanitize([d.dict() for d in docs], allow_bson=True),
+                jsanitize([d.model_dump() for d in docs], allow_bson=True),
                 pd_docs,
             )
 
diff --git a/emmet-builders/emmet/builders/mobility/migration_graph.py b/emmet-builders/emmet/builders/mobility/migration_graph.py
index 0f74d07..a77172f 100644
--- a/emmet-builders/emmet/builders/mobility/migration_graph.py
+++ b/emmet-builders/emmet/builders/mobility/migration_graph.py
@@ -99,4 +99,4 @@ class MigrationGraphBuilder(MapBuilder):
             self.logger.error(f"error getting MigrationGraphDoc: {e}")
             return jsanitize(mg_doc)
 
-        return jsanitize(mg_doc.dict())
+        return jsanitize(mg_doc.model_dump())
diff --git a/emmet-builders/emmet/builders/molecules/atomic.py b/emmet-builders/emmet/builders/molecules/atomic.py
index 9524ce6..18b7a49 100644
--- a/emmet-builders/emmet/builders/molecules/atomic.py
+++ b/emmet-builders/emmet/builders/molecules/atomic.py
@@ -273,7 +273,7 @@ class PartialChargesBuilder(Builder):
 
         self.logger.debug(f"Produced {len(charges_docs)} charges docs for {formula}")
 
-        return jsanitize([doc.dict() for doc in charges_docs], allow_bson=True)
+        return jsanitize([doc.model_dump() for doc in charges_docs], allow_bson=True)
 
     def update_targets(self, items: List[List[Dict]]):
         """
@@ -555,7 +555,7 @@ class PartialSpinsBuilder(Builder):
             f"Produced {len(spins_docs)} partial spins docs for {formula}"
         )
 
-        return jsanitize([doc.dict() for doc in spins_docs], allow_bson=True)
+        return jsanitize([doc.model_dump() for doc in spins_docs], allow_bson=True)
 
     def update_targets(self, items: List[List[Dict]]):
         """
diff --git a/emmet-builders/emmet/builders/molecules/bonds.py b/emmet-builders/emmet/builders/molecules/bonds.py
index 80426f0..4a49409 100644
--- a/emmet-builders/emmet/builders/molecules/bonds.py
+++ b/emmet-builders/emmet/builders/molecules/bonds.py
@@ -290,7 +290,7 @@ class BondingBuilder(Builder):
 
         self.logger.debug(f"Produced {len(bonding_docs)} bonding docs for {formula}")
 
-        return jsanitize([doc.dict() for doc in bonding_docs], allow_bson=True)
+        return jsanitize([doc.model_dump() for doc in bonding_docs], allow_bson=True)
 
     def update_targets(self, items: List[List[Dict]]):
         """
diff --git a/emmet-builders/emmet/builders/molecules/metal_binding.py b/emmet-builders/emmet/builders/molecules/metal_binding.py
index a3d5ad2..68c119a 100644
--- a/emmet-builders/emmet/builders/molecules/metal_binding.py
+++ b/emmet-builders/emmet/builders/molecules/metal_binding.py
@@ -490,7 +490,7 @@ class MetalBindingBuilder(Builder):
             f"Produced {len(binding_docs)} metal binding docs for {formula}"
         )
 
-        return jsanitize([doc.dict() for doc in binding_docs], allow_bson=True)
+        return jsanitize([doc.model_dump() for doc in binding_docs], allow_bson=True)
 
     def update_targets(self, items: List[List[Dict]]):
         """
diff --git a/emmet-builders/emmet/builders/molecules/orbitals.py b/emmet-builders/emmet/builders/molecules/orbitals.py
index d1eae7d..c6ece5c 100644
--- a/emmet-builders/emmet/builders/molecules/orbitals.py
+++ b/emmet-builders/emmet/builders/molecules/orbitals.py
@@ -255,7 +255,7 @@ class OrbitalBuilder(Builder):
 
         self.logger.debug(f"Produced {len(orbital_docs)} orbital docs for {formula}")
 
-        return jsanitize([doc.dict() for doc in orbital_docs], allow_bson=True)
+        return jsanitize([doc.model_dump() for doc in orbital_docs], allow_bson=True)
 
     def update_targets(self, items: List[List[Dict]]):
         """
diff --git a/emmet-builders/emmet/builders/molecules/redox.py b/emmet-builders/emmet/builders/molecules/redox.py
index 257a3e7..a1780d7 100644
--- a/emmet-builders/emmet/builders/molecules/redox.py
+++ b/emmet-builders/emmet/builders/molecules/redox.py
@@ -357,7 +357,7 @@ class RedoxBuilder(Builder):
         self.logger.debug(f"Produced {len(redox_docs)} redox docs for {formula}")
 
         return jsanitize(
-            [doc.dict() for doc in redox_docs if doc is not None], allow_bson=True
+            [doc.model_dump() for doc in redox_docs if doc is not None], allow_bson=True
         )
 
     def update_targets(self, items: List[List[Dict]]):
diff --git a/emmet-builders/emmet/builders/molecules/summary.py b/emmet-builders/emmet/builders/molecules/summary.py
index 5df8137..e36bfcd 100644
--- a/emmet-builders/emmet/builders/molecules/summary.py
+++ b/emmet-builders/emmet/builders/molecules/summary.py
@@ -350,7 +350,7 @@ class SummaryBuilder(Builder):
 
         self.logger.debug(f"Produced {len(summary_docs)} summary docs for {formula}")
 
-        return jsanitize([doc.dict() for doc in summary_docs], allow_bson=True)
+        return jsanitize([doc.model_dump() for doc in summary_docs], allow_bson=True)
 
     def update_targets(self, items: List[List[Dict]]):
         """
diff --git a/emmet-builders/emmet/builders/molecules/thermo.py b/emmet-builders/emmet/builders/molecules/thermo.py
index 4cd9cca..9495dbc 100644
--- a/emmet-builders/emmet/builders/molecules/thermo.py
+++ b/emmet-builders/emmet/builders/molecules/thermo.py
@@ -467,7 +467,7 @@ class ThermoBuilder(Builder):
 
         self.logger.debug(f"Produced {len(thermo_docs)} thermo docs for {formula}")
 
-        return jsanitize([doc.dict() for doc in thermo_docs], allow_bson=True)
+        return jsanitize([doc.model_dump() for doc in thermo_docs], allow_bson=True)
 
     def update_targets(self, items: List[List[Dict]]):
         """
diff --git a/emmet-builders/emmet/builders/molecules/vibration.py b/emmet-builders/emmet/builders/molecules/vibration.py
index 0c7f494..39c4eca 100644
--- a/emmet-builders/emmet/builders/molecules/vibration.py
+++ b/emmet-builders/emmet/builders/molecules/vibration.py
@@ -245,7 +245,7 @@ class VibrationBuilder(Builder):
 
         self.logger.debug(f"Produced {len(vibe_docs)} vibration docs for {formula}")
 
-        return jsanitize([doc.dict() for doc in vibe_docs], allow_bson=True)
+        return jsanitize([doc.model_dump() for doc in vibe_docs], allow_bson=True)
 
     def update_targets(self, items: List[List[Dict]]):
         """
diff --git a/emmet-builders/emmet/builders/qchem/molecules.py b/emmet-builders/emmet/builders/qchem/molecules.py
index c8840d6..4e1e1a9 100644
--- a/emmet-builders/emmet/builders/qchem/molecules.py
+++ b/emmet-builders/emmet/builders/qchem/molecules.py
@@ -283,7 +283,7 @@ class MoleculesAssociationBuilder(Builder):
 
         self.logger.debug(f"Produced {len(molecules)} molecules for {shash}")
 
-        return jsanitize([mol.dict() for mol in molecules], allow_bson=True)
+        return jsanitize([mol.model_dump() for mol in molecules], allow_bson=True)
 
     def update_targets(self, items: List[List[Dict]]):
         """
@@ -648,7 +648,9 @@ class MoleculesBuilder(Builder):
 
         self.logger.debug(f"Produced {len(complete_mol_docs)} molecules for {formula}")
 
-        return jsanitize([mol.dict() for mol in complete_mol_docs], allow_bson=True)
+        return jsanitize(
+            [mol.model_dump() for mol in complete_mol_docs], allow_bson=True
+        )
 
     def update_targets(self, items: List[List[Dict]]):
         """
diff --git a/emmet-builders/emmet/builders/vasp/materials.py b/emmet-builders/emmet/builders/vasp/materials.py
index 23577b3..2933ab4 100644
--- a/emmet-builders/emmet/builders/vasp/materials.py
+++ b/emmet-builders/emmet/builders/vasp/materials.py
@@ -259,7 +259,7 @@ class MaterialsBuilder(Builder):
 
         self.logger.debug(f"Produced {len(materials)} materials for {formula}")
 
-        return jsanitize([mat.dict() for mat in materials], allow_bson=True)
+        return jsanitize([mat.model_dump() for mat in materials], allow_bson=True)
 
     def update_targets(self, items: List[List[Dict]]):
         """
diff --git a/emmet-core/emmet/core/_general_store.py b/emmet-core/emmet/core/_general_store.py
index a0fa8f1..4b269f9 100644
--- a/emmet-core/emmet/core/_general_store.py
+++ b/emmet-core/emmet/core/_general_store.py
@@ -2,9 +2,9 @@ from pydantic import BaseModel, Field
 from typing import Dict
 
 try:
-    from typing import Literal  # type: ignore
+    from typing import Literal, Optional  # type: ignore
 except ImportError:
-    from typing_extensions import Literal  # type: ignore
+    from typing_extensions import Literal, Optional  # type: ignore
 from datetime import datetime
 
 
@@ -13,13 +13,13 @@ class GeneralStoreDoc(BaseModel):
     Defines general store data
     """
 
-    kind: Literal["newsfeed", "seminar", "banner"] = Field(
+    kind: Optional[Literal["newsfeed", "seminar", "banner"]] = Field(
         None, description="Type of the data."
     )
 
-    markdown: str = Field(None, description="Markdown data.")
+    markdown: Optional[str] = Field(None, description="Markdown data.")
 
-    meta: Dict = Field(None, description="Metadata.")
+    meta: Optional[Dict] = Field(None, description="Metadata.")
 
     last_updated: datetime = Field(
         description="Timestamp for when this document was last updated",
diff --git a/emmet-core/emmet/core/_messages.py b/emmet-core/emmet/core/_messages.py
index ffc83e8..bc51486 100644
--- a/emmet-core/emmet/core/_messages.py
+++ b/emmet-core/emmet/core/_messages.py
@@ -1,4 +1,4 @@
-from typing import List
+from typing import List, Optional
 from datetime import datetime
 from pydantic import BaseModel, Field
 from enum import Enum
@@ -14,15 +14,17 @@ class MessagesDoc(BaseModel):
     Defines data for user messages
     """
 
-    title: str = Field(
+    title: Optional[str] = Field(
         None,
         title="Title",
         description="Generic title or short summary for the message.",
     )
 
-    body: str = Field(None, title="Body", description="Main text body of message.")
+    body: Optional[str] = Field(
+        None, title="Body", description="Main text body of message."
+    )
 
-    authors: List[str] = Field(
+    authors: Optional[List[str]] = Field(
         None,
         title="Title",
         description="Generic title or short summary for the message.",
diff --git a/emmet-core/emmet/core/_user_settings.py b/emmet-core/emmet/core/_user_settings.py
index 075bebc..6c25bcc 100644
--- a/emmet-core/emmet/core/_user_settings.py
+++ b/emmet-core/emmet/core/_user_settings.py
@@ -1,4 +1,5 @@
 from pydantic import BaseModel, Field
+from typing import Optional
 
 
 class UserSettingsDoc(BaseModel):
@@ -6,11 +7,11 @@ class UserSettingsDoc(BaseModel):
     Defines data for user settings
     """
 
-    consumer_id: str = Field(
+    consumer_id: Optional[str] = Field(
         None, title="Consumer ID", description="Consumer ID for a specific user."
     )
 
-    settings: dict = Field(
+    settings: Optional[dict] = Field(
         None,
         title="Consumer ID settings",
         description="Settings defined for a specific user.",
diff --git a/emmet-core/emmet/core/absorption.py b/emmet-core/emmet/core/absorption.py
index 81d81e0..6850c1e 100644
--- a/emmet-core/emmet/core/absorption.py
+++ b/emmet-core/emmet/core/absorption.py
@@ -1,4 +1,4 @@
-from typing import List
+from typing import List, Optional
 from pydantic import Field
 from emmet.core.material_property import PropertyDoc
 import numpy as np
@@ -9,7 +9,7 @@ from pymatgen.core import Structure
 class AbsorptionDoc(PropertyDoc):
     """Absorption spectrum based on frequency dependent dielectric function calculations."""
 
-    property_name = "Optical absorption spectrum"
+    property_name: str = "Optical absorption spectrum"
 
     task_id: str = Field(..., description="Calculation id")
 
@@ -34,9 +34,9 @@ class AbsorptionDoc(PropertyDoc):
         description="Real part of the dielectric function corresponding to the energies",
     )
 
-    bandgap: float = Field(None, description="The electronic band gap")
+    bandgap: Optional[float] = Field(None, description="The electronic band gap")
 
-    nkpoints: float = Field(
+    nkpoints: Optional[float] = Field(
         None, description="The number of kpoints used in the calculation"
     )
 
diff --git a/emmet-core/emmet/core/base.py b/emmet-core/emmet/core/base.py
index 80bb85b..d8a5ea8 100644
--- a/emmet-core/emmet/core/base.py
+++ b/emmet-core/emmet/core/base.py
@@ -2,9 +2,9 @@
 
 """ Base emmet model to add default metadata """
 from datetime import datetime
-from typing import TypeVar
+from typing import TypeVar, Optional
 
-from pydantic import BaseModel, Field, validator
+from pydantic import field_validator, BaseModel, Field
 from pymatgen.core import __version__ as pmg_version
 from monty.json import MontyDecoder
 
@@ -27,11 +27,11 @@ class EmmetMeta(BaseModel):
         pmg_version, description="The version of pymatgen this document was built with."
     )
 
-    pull_request: int = Field(
+    pull_request: Optional[int] = Field(
         None, description="The pull request number associated with this data build."
     )
 
-    database_version: str = Field(
+    database_version: Optional[str] = Field(
         None, description="The database version for the built data."
     )
 
@@ -41,7 +41,8 @@ class EmmetMeta(BaseModel):
     )
 
     # Make sure that the datetime field is properly formatted
-    @validator("build_date", pre=True)
+    @field_validator("build_date", mode="before")
+    @classmethod
     def build_date_dict_ok(cls, v):
         return monty_decoder.process_decoded(v)
 
@@ -54,3 +55,7 @@ class EmmetBaseModel(BaseModel):
     builder_meta: EmmetMeta = Field(
         default_factory=EmmetMeta, description="Builder metadata."
     )
+
+    def dict(self, **kwargs):  # noqa: A003
+        """Same as model_dump(), without the deprecation warning: builders still call it in hot loops."""
+        return self.model_dump(**kwargs)
diff --git a/emmet-core/emmet/core/bonds.py b/emmet-core/emmet/core/bonds.py
index 07eb659..7426353 100644
--- a/emmet-core/emmet/core/bonds.py
+++ b/emmet-core/emmet/core/bonds.py
@@ -15,7 +15,7 @@ class BondingDoc(PropertyDoc):
     """Structure graphs representing chemical bonds calculated from structure
     using near neighbor strategies as defined in pymatgen."""
 
-    property_name = "bonding"
+    property_name: str = "bonding"
 
     structure_graph: StructureGraph = Field(
         description="Structure graph",
diff --git a/emmet-core/emmet/core/charge_density.py b/emmet-core/emmet/core/charge_density.py
index 9dc97d0..e095225 100644
--- a/emmet-core/emmet/core/charge_density.py
+++ b/emmet-core/emmet/core/charge_density.py
@@ -1,5 +1,6 @@
-from pydantic import BaseModel, Field
+from pydantic import ConfigDict, BaseModel, Field
 from datetime import datetime
+from typing import Optional
 
 
 class ChgcarDataDoc(BaseModel):
@@ -7,20 +8,18 @@ class ChgcarDataDoc(BaseModel):
     Electron charge density metadata for selected materials.
     """
 
-    fs_id: str = Field(
+    fs_id: Optional[str] = Field(
         None, description="Unique object ID for the charge density data."
     )
 
-    last_updated: datetime = Field(
+    last_updated: Optional[datetime] = Field(
         None,
         description="Timestamp for the most recent update to the charge density data.",
     )
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The Materials Project ID of the calculation producing the charge density data. "
         "This comes in the form: mp-******.",
     )
-
-    class Config:
-        extra = "allow"
+    model_config = ConfigDict(extra="allow")
diff --git a/emmet-core/emmet/core/chemenv.py b/emmet-core/emmet/core/chemenv.py
index 73754f0..daf1196 100644
--- a/emmet-core/emmet/core/chemenv.py
+++ b/emmet-core/emmet/core/chemenv.py
@@ -1,4 +1,4 @@
-from typing import Literal, List, Union
+from typing import Literal, List, Union, Optional
 
 from pydantic import Field
 from pymatgen.analysis.chemenv.coordination_environments.chemenv_strategies import (
@@ -315,14 +315,14 @@ class ChemEnvDoc(PropertyDoc):
     If no oxidation states are available, all bonds will be considered as a fall-back.
     """
 
-    property_name = "coord_environment"
+    property_name: str = "coord_environment"
 
     structure: Structure = Field(
         ...,
         description="The structure used in the generation of the chemical environment data",
     )
 
-    valences: List[int] = Field(
+    valences: List[Union[int, float]] = Field(
         description="List of valences for each site in this material to determine cations"
     )
 
@@ -371,7 +371,7 @@ class ChemEnvDoc(PropertyDoc):
         description="List of Wyckoff positions for unique (cationic) species in structure."
     )
 
-    warnings: Union[str, None] = Field(None, description="Warning")
+    warnings: Optional[str] = Field(None, description="Warning")
 
     @classmethod
     def from_structure(
diff --git a/emmet-core/emmet/core/corrected_entries.py b/emmet-core/emmet/core/corrected_entries.py
index cc76c66..8b112bd 100644
--- a/emmet-core/emmet/core/corrected_entries.py
+++ b/emmet-core/emmet/core/corrected_entries.py
@@ -16,7 +16,7 @@ class CorrectedEntriesDoc(EmmetBaseModel):
     A corrected entries document
     """
 
-    property_name = "corrected_entries"
+    property_name: str = "corrected_entries"
 
     chemsys: str = Field(
         ...,
diff --git a/emmet-core/emmet/core/dois.py b/emmet-core/emmet/core/dois.py
index 6b55435..3bb06d4 100644
--- a/emmet-core/emmet/core/dois.py
+++ b/emmet-core/emmet/core/dois.py
@@ -1,4 +1,5 @@
 from pydantic import BaseModel, Field
+from typing import Optional
 
 
 class DOIDoc(BaseModel):
@@ -6,17 +7,17 @@ class DOIDoc(BaseModel):
     DOIs to reference specific materials on Materials Project.
     """
 
-    doi: str = Field(
+    doi: Optional[str] = Field(
         None,
         description="DOI of the material.",
     )
 
-    bibtex: str = Field(
+    bibtex: Optional[str] = Field(
         None,
         description="Bibtex reference of the material.",
     )
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The Materials Project ID of the material. This comes in the form: mp-******.",
     )
diff --git a/emmet-core/emmet/core/elasticity.py b/emmet-core/emmet/core/elasticity.py
index b4464b2..6cfd18b 100644
--- a/emmet-core/emmet/core/elasticity.py
+++ b/emmet-core/emmet/core/elasticity.py
@@ -19,58 +19,72 @@ SETTINGS = EmmetSettings()
 
 
 class ElasticTensorDoc(BaseModel):
-    raw: MatrixVoigt = Field(
+    raw: Optional[MatrixVoigt] = Field(
         None,
         description="Elastic tensor corresponding to structure orientation (GPa)",
     )
-    ieee_format: MatrixVoigt = Field(
+    ieee_format: Optional[MatrixVoigt] = Field(
         None,
         description="Elastic tensor corresponding to IEEE orientation (GPa)",
     )
 
 
 class ComplianceTensorDoc(BaseModel):
-    raw: MatrixVoigt = Field(
+    raw: Optional[MatrixVoigt] = Field(
         None,
         description="Compliance tensor corresponding to structure orientation (TPa^-1)",
     )
-    ieee_format: MatrixVoigt = Field(
+    ieee_format: Optional[MatrixVoigt] = Field(
         None,
         description="Compliance tensor corresponding to IEEE orientation (TPa^-1)",
     )
 
 
 class BulkModulus(BaseModel):
-    voigt: float = Field(None, description="Bulk modulus Voigt average (GPa)")
-    reuss: float = Field(None, description="Bulk modulus Reuss average (Gpa)")
-    vrh: float = Field(None, description="Bulk modulus Voigt-Reuss-Hill average (GPa)")
+    voigt: Optional[float] = Field(None, description="Bulk modulus Voigt average (GPa)")
+    reuss: Optional[float] = Field(None, description="Bulk modulus Reuss average (Gpa)")
+    vrh: Optional[float] = Field(
+        None, description="Bulk modulus Voigt-Reuss-Hill average (GPa)"
+    )
 
 
 class ShearModulus(BaseModel):
-    voigt: float = Field(None, description="Shear modulus Voigt average (GPa)")
-    reuss: float = Field(None, description="Shear modulus Reuss average (GPa)")
-    vrh: float = Field(None, description="Shear modulus Voigt-Reuss-Hill average (GPa)")
+    voigt: Optional[float] = Field(
+        None, description="Shear modulus Voigt average (GPa)"
+    )
+    reuss: Optional[float] = Field(
+        None, description="Shear modulus Reuss average (GPa)"
+    )
+    vrh: Optional[float] = Field(
+        None, description="Shear modulus Voigt-Reuss-Hill average (GPa)"
+    )
 
 
 class SoundVelocity(BaseModel):
-    transverse: float = Field(None, description="Transverse sound velocity (SI units)")
-    longitudinal: float = Field(
+    transverse: Optional[float] = Field(
+        None, description="Transverse sound velocity (SI units)"
+    )
+    longitudinal: Optional[float] = Field(
         None, description="Longitudinal sound velocity (SI units)"
     )
-    snyder_acoustic: float = Field(
+    snyder_acoustic: Optional[float] = Field(
         None, description="Snyder's acoustic sound velocity (SI units)"
     )
-    snyder_optical: float = Field(
+    snyder_optical: Optional[float] = Field(
         None, description="Snyder's optical sound velocity (SI units)"
     )
-    snyder_total: float = Field(
+    snyder_total: Optional[float] = Field(
         None, description="Snyder's total sound velocity (SI units)"
     )
 
 
 class ThermalConductivity(BaseModel):
-    clarke: float = Field(None, description="Clarke's thermal conductivity (SI units)")
-    cahill: float = Field(None, description="Cahill's thermal conductivity (SI units)")
+    clarke: Optional[float] = Field(
+        None, description="Clarke's thermal conductivity (SI units)"
+    )
+    cahill: Optional[float] = Field(
+        None, description="Cahill's thermal conductivity (SI units)"
+    )
 
 
 class FittingData(BaseModel):
@@ -95,27 +109,27 @@ class FittingData(BaseModel):
     second_pk_stresses: List[Matrix3D] = Field(
         description="Second Piola-Kirchhoff stress tensors on structures"
     )
-    deformation_tasks: List[MPID] = Field(
+    deformation_tasks: Optional[List[MPID]] = Field(
         None,
         description="Deformation task ids corresponding to the strained structures",
     )
-    deformation_dir_names: List[str] = Field(
+    deformation_dir_names: Optional[List[str]] = Field(
         None, description="Paths to the running directories of deformation tasks"
     )
 
     # data of equilibrium structure
-    equilibrium_cauchy_stress: Matrix3D = Field(
+    equilibrium_cauchy_stress: Optional[Matrix3D] = Field(
         None, description="Cauchy stress tensor of the relaxed structure"
     )
-    optimization_task: MPID = Field(
+    optimization_task: Optional[MPID] = Field(
         None, description="Optimization task corresponding to the relaxed structure"
     )
-    optimization_dir_name: str = Field(
+    optimization_dir_name: Optional[str] = Field(
         None, description="Path to the running directory of the optimization task"
     )
 
     # derived strains stresses
-    num_total_strain_stress_states: int = Field(
+    num_total_strain_stress_states: Optional[int] = Field(
         None,
         description="Number of total strain--stress states used for fitting, i.e. the "
         "sum of explicitly calculated deformations and derived deformations from "
@@ -124,39 +138,39 @@ class FittingData(BaseModel):
 
 
 class CriticalMessage(BaseModel):
-    FITTING = "Critical: cannot fit elastic tensor. Error: {}."
-    COMPLIANCE = (
+    FITTING: str = "Critical: cannot fit elastic tensor. Error: {}."
+    COMPLIANCE: str = (
         "Critical: cannot invert elastic tensor to get compliance tensor. Error: {}."
     )
-    STRAIN_RANK = (
+    STRAIN_RANK: str = (
         "Critical: insufficient number of valid strains. Expect the matrix of all "
         "strains to be of rank 6; got rank {}."
     )
-    N_STATES = (
+    N_STATES: str = (
         "Critical: Expect 24 total (primary plus derived) strain--stress states "
         "to fit the data; got {}."
     )
 
 
 class WarningMessage(BaseModel):
-    NEGATIVE_EIGVAL = (
+    NEGATIVE_EIGVAL: str = (
         "Elastic tensor has negative eigenvalue(s), indicating that the structure is "
         "mechanically unstable."
     )  # https://doi.org/10.1103/PhysRevB.90.224104
-    NEGATIVE_MODULUS = (
+    NEGATIVE_MODULUS: str = (
         "Negative modulus: {} {} is {}, indicating that the structure is mechanically "
         "unstable."
     )
-    SMALL_MODULUS = "Small modulus. {} {} is {}; smaller than {}."
-    LARGE_MODULUS = "Large modulus. {} {} is {}; larger than {}."
-    LARGE_YOUNG_MODULUS = "Large Young's modulus {}; larger than {}."
-    LARGE_COMPONENT = "Elastic tensor has component larger than {}."
+    SMALL_MODULUS: str = "Small modulus. {} {} is {}; smaller than {}."
+    LARGE_MODULUS: str = "Large modulus. {} {} is {}; larger than {}."
+    LARGE_YOUNG_MODULUS: str = "Large Young's modulus {}; larger than {}."
+    LARGE_COMPONENT: str = "Elastic tensor has component larger than {}."
 
 
 class ElasticityDoc(PropertyDoc):
     property_name: str = "elasticity"
 
-    structure: Structure = Field(
+    structure: Optional[Structure] = Field(
         None, description="Structure to compute the elasticity"
     )
 
@@ -164,17 +178,19 @@ class ElasticityDoc(PropertyDoc):
         default=2, description="Order of the expansion of the elastic tensor"
     )
 
-    elastic_tensor: ElasticTensorDoc = Field(None, description="Elastic tensor")
+    elastic_tensor: Optional[ElasticTensorDoc] = Field(
+        None, description="Elastic tensor"
+    )
 
-    compliance_tensor: ComplianceTensorDoc = Field(
+    compliance_tensor: Optional[ComplianceTensorDoc] = Field(
         None, description="Compliance tensor"
     )
 
     # derived properties
-    bulk_modulus: BulkModulus = Field(None, description="Bulk modulus")
-    shear_modulus: ShearModulus = Field(None, description="Shear modulus")
-    sound_velocity: SoundVelocity = Field(None, description="Sound velocity")
-    thermal_conductivity: ThermalConductivity = Field(
+    bulk_modulus: Optional[BulkModulus] = Field(None, description="Bulk modulus")
+    shear_modulus: Optional[ShearModulus] = Field(None, description="Shear modulus")
+    sound_velocity: Optional[SoundVelocity] = Field(None, description="Sound velocity")
+    thermal_conductivity: Optional[ThermalConductivity] = Field(
         None, description="Thermal conductivity"
     )
     young_modulus: float = Field(
@@ -183,18 +199,22 @@ class ElasticityDoc(PropertyDoc):
     universal_anisotropy: float = Field(
         None, description="Universal elastic anisotropy"
     )
-    homogeneous_poisson: float = Field(None, description="Homogeneous Poisson ratio")
-    debye_temperature: float = Field(None, description="Debye temperature (SI units)")
+    homogeneous_poisson: Optional[float] = Field(
+        None, description="Homogeneous Poisson ratio"
+    )
+    debye_temperature: Optional[float] = Field(
+        None, description="Debye temperature (SI units)"
+    )
 
-    fitting_data: FittingData = Field(
+    fitting_data: Optional[FittingData] = Field(
         None, description="Data used to fit the elastic tensor"
     )
 
-    fitting_method: str = Field(
+    fitting_method: Optional[str] = Field(
         None, description="Method used to fit the elastic tensor"
     )
 
-    state: Status = Field(
+    state: Optional[Status] = Field(
         None,
         description="State of the fitting/analysis: `successful` or `failed`",
     )
@@ -655,7 +675,7 @@ def sanity_check(
         warnings.append(CM.STRAIN_RANK.format(rank))
 
     # elastic tensor eigenvalues
-    eig_vals, _ = np.linalg.eig(elastic_doc.raw)
+    eig_vals, _ = np.linalg.eig(elastic_doc.raw)  # type: ignore
     if np.any(eig_vals < 0.0):
         warnings.append(WM.NEGATIVE_EIGVAL)
 
@@ -671,7 +691,7 @@ def sanity_check(
     high = 1000.0
     for p in ["bulk_modulus", "shear_modulus"]:
         doc = derived_props[p]
-        doc = doc.dict()
+        doc = doc.model_dump()
         p = p.replace("_", " ")
         for name in ["voigt", "reuss", "vrh"]:
             v = doc[name]
diff --git a/emmet-core/emmet/core/elasticity_legacy.py b/emmet-core/emmet/core/elasticity_legacy.py
index 1ac84ee..e34ddce 100644
--- a/emmet-core/emmet/core/elasticity_legacy.py
+++ b/emmet-core/emmet/core/elasticity_legacy.py
@@ -1,4 +1,4 @@
-from typing import List
+from typing import List, Optional
 from pydantic import BaseModel, Field
 
 
@@ -7,52 +7,52 @@ class ElasticityData(BaseModel):
     Elastic tensors and associated information.
     """
 
-    k_voigt: float = Field(
+    k_voigt: Optional[float] = Field(
         None,
         description="Voigt average of the bulk modulus in GPa.",
     )
 
-    k_reuss: float = Field(
+    k_reuss: Optional[float] = Field(
         None,
         description="Reuss average of the bulk modulus in GPa.",
     )
 
-    k_vrh: float = Field(
+    k_vrh: Optional[float] = Field(
         None,
         description="Voigt-Reuss-Hill average of the bulk modulus in GPa.",
     )
 
-    g_voigt: float = Field(
+    g_voigt: Optional[float] = Field(
         None,
         description="Voigt average of the shear modulus in GPa.",
     )
 
-    g_reuss: float = Field(
+    g_reuss: Optional[float] = Field(
         None,
         description="Reuss average of the shear modulus in GPa.",
     )
 
-    g_vrh: float = Field(
+    g_vrh: Optional[float] = Field(
         None,
         description="Voigt-Reuss-Hill average of the shear modulus in GPa.",
     )
 
-    universal_anisotropy: float = Field(
+    universal_anisotropy: Optional[float] = Field(
         None,
         description="Elastic anisotropy.",
     )
 
-    homogeneous_poisson: float = Field(
+    homogeneous_poisson: Optional[float] = Field(
         None,
         description="Poisson's ratio.",
     )
 
-    elastic_tensor: List[List[float]] = Field(
+    elastic_tensor: Optional[List[List[float]]] = Field(
         None,
         description="Stiffness tensor in GPa.",
     )
 
-    compliance_tensor: List[List[float]] = Field(
+    compliance_tensor: Optional[List[List[float]]] = Field(
         None,
         description="Compliance tensor in 10^(-12)/Pa.",
     )
@@ -63,22 +63,22 @@ class ElasticityDoc(BaseModel):
     Model for a document containing elasticity data
     """
 
-    pretty_formula: str = Field(
+    pretty_formula: Optional[str] = Field(
         None,
         description="Cleaned representation of the material formula",
     )
 
-    chemsys: str = Field(
+    chemsys: Optional[str] = Field(
         None,
         description="Dash-delimited string of elements in the material.",
     )
 
-    elasticity: ElasticityData = Field(
+    elasticity: Optional[ElasticityData] = Field(
         None,
         description="Elasticity data for the material.",
     )
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The Materials Project ID of the material. This comes in the form: mp-******.",
     )
diff --git a/emmet-core/emmet/core/electrode.py b/emmet-core/emmet/core/electrode.py
index d688613..f1a220d 100644
--- a/emmet-core/emmet/core/electrode.py
+++ b/emmet-core/emmet/core/electrode.py
@@ -1,12 +1,12 @@
 import re
 from datetime import datetime
-from typing import List, Union, Dict
+from typing import List, Union, Dict, Optional
 from collections import defaultdict
 
 from emmet.core.utils import ValueEnum
 
 from monty.json import MontyDecoder
-from pydantic import BaseModel, Field, validator
+from pydantic import field_validator, BaseModel, Field
 from pymatgen.apps.battery.battery_abc import AbstractElectrode
 from pymatgen.apps.battery.conversion_battery import ConversionElectrode
 from pymatgen.apps.battery.insertion_battery import InsertionElectrode
@@ -34,41 +34,45 @@ class VoltagePairDoc(BaseModel):
         object to gain access to some basic statistics about the voltage step
     """
 
-    formula_charge: str = Field(
+    formula_charge: Optional[str] = Field(
         None, description="The chemical formula of the charged material."
     )
 
-    formula_discharge: str = Field(
+    formula_discharge: Optional[str] = Field(
         None, description="The chemical formula of the discharged material."
     )
 
-    max_delta_volume: float = Field(
+    max_delta_volume: Optional[float] = Field(
         None,
         description="Volume changes in % for a particular voltage step using: "
         "max(charge, discharge) / min(charge, discharge) - 1.",
     )
 
-    average_voltage: float = Field(
+    average_voltage: Optional[float] = Field(
         None, description="The average voltage in V for a particular voltage step."
     )
 
-    capacity_grav: float = Field(None, description="Gravimetric capacity in mAh/g.")
+    capacity_grav: Optional[float] = Field(
+        None, description="Gravimetric capacity in mAh/g."
+    )
 
-    capacity_vol: float = Field(None, description="Volumetric capacity in mAh/cc.")
+    capacity_vol: Optional[float] = Field(
+        None, description="Volumetric capacity in mAh/cc."
+    )
 
-    energy_grav: float = Field(
+    energy_grav: Optional[float] = Field(
         None, description="Gravimetric energy (Specific energy) in Wh/kg."
     )
 
-    energy_vol: float = Field(
+    energy_vol: Optional[float] = Field(
         None, description="Volumetric energy (Energy Density) in Wh/l."
     )
 
-    fracA_charge: float = Field(
+    fracA_charge: Optional[float] = Field(
         None, description="Atomic fraction of the working ion in the charged state."
     )
 
-    fracA_discharge: float = Field(
+    fracA_discharge: Optional[float] = Field(
         None, description="Atomic fraction of the working ion in the discharged state."
     )
 
@@ -85,19 +89,19 @@ class InsertionVoltagePairDoc(VoltagePairDoc):
     Features specific to insertion electrode
     """
 
-    stability_charge: float = Field(
+    stability_charge: Optional[float] = Field(
         None, description="The energy above hull of the charged material in eV/atom."
     )
 
-    stability_discharge: float = Field(
+    stability_discharge: Optional[float] = Field(
         None, description="The energy above hull of the discharged material in eV/atom."
     )
 
-    id_charge: Union[MPID, int, None] = Field(
+    id_charge: Optional[Union[MPID, int, None]] = Field(
         None, description="The Materials Project ID of the charged structure."
     )
 
-    id_discharge: Union[MPID, int, None] = Field(
+    id_discharge: Optional[Union[MPID, int, None]] = Field(
         None, description="The Materials Project ID of the discharged structure."
     )
 
@@ -107,7 +111,7 @@ class ConversionVoltagePairDoc(VoltagePairDoc):
     Features specific to conversion electrode
     """
 
-    reaction: dict = Field(
+    reaction: Optional[dict] = Field(
         None,
         description="The reaction that characterizes that particular voltage step.",
     )
@@ -119,27 +123,27 @@ class EntriesCompositionSummary(BaseModel):
     Included to enable better searching via the API.
     """
 
-    all_formulas: List[str] = Field(
+    all_formulas: Optional[List[str]] = Field(
         None,
         description="Reduced formulas for material entries across all voltage pairs.",
     )
 
-    all_chemsys: List[str] = Field(
+    all_chemsys: Optional[List[str]] = Field(
         None,
         description="Chemical systems for material entries across all voltage pairs.",
     )
 
-    all_formula_anonymous: List[str] = Field(
+    all_formula_anonymous: Optional[List[str]] = Field(
         None,
         description="Anonymous formulas for material entries across all voltage pairs.",
     )
 
-    all_elements: List[Element] = Field(
+    all_elements: Optional[List[Element]] = Field(
         None,
         description="Elements in material entries across all voltage pairs.",
     )
 
-    all_composition_reduced: Dict = Field(
+    all_composition_reduced: Optional[Dict] = Field(
         None,
         description="Composition reduced data for entries across all voltage pairs.",
     )
@@ -169,69 +173,69 @@ class EntriesCompositionSummary(BaseModel):
 
 
 class BaseElectrode(BaseModel):
-    battery_type: BatteryType = Field(
+    battery_type: Optional[BatteryType] = Field(
         None, description="The type of battery (insertion or conversion)."
     )
 
-    battery_id: str = Field(
+    battery_id: Optional[str] = Field(
         None,
         description="The id for this battery document is the numerically smallest material_id followed by "
         "the working ion.",
     )
 
-    thermo_type: str = Field(
+    thermo_type: Optional[str] = Field(
         None,
         description="The functional type used to compute the thermodynamics of this electrode document.",
     )
 
-    battery_formula: str = Field(
+    battery_formula: Optional[str] = Field(
         None,
         description="Reduced formula with working ion range produced by combining the charge and discharge formulas.",
     )
 
-    working_ion: Element = Field(
+    working_ion: Optional[Element] = Field(
         None, description="The working ion as an Element object."
     )
 
-    num_steps: int = Field(
+    num_steps: Optional[int] = Field(
         None,
         description="The number of distinct voltage steps in from fully charge to "
         "discharge based on the stable intermediate states.",
     )
 
-    max_voltage_step: float = Field(
+    max_voltage_step: Optional[float] = Field(
         None, description="Maximum absolute difference in adjacent voltage steps."
     )
 
-    last_updated: datetime = Field(
+    last_updated: Optional[datetime] = Field(
         None,
         description="Timestamp for the most recent calculation for this Material document.",
     )
 
-    framework: Composition = Field(
+    framework: Optional[Composition] = Field(
         None, description="The chemical compositions of the host framework."
     )
 
-    framework_formula: str = Field(
+    framework_formula: Optional[str] = Field(
         None, description="The id for this battery document."
     )
 
-    elements: List[Element] = Field(
+    elements: Optional[List[Element]] = Field(
         None,
         description="The atomic species contained in this electrode (not including the working ion).",
     )
 
-    nelements: int = Field(
+    nelements: Optional[int] = Field(
         None,
         description="The number of elements in the material (not including the working ion).",
     )
 
-    chemsys: str = Field(
+    chemsys: Optional[str] = Field(
         None,
         description="The chemical system this electrode belongs to (not including the working ion).",
     )
 
-    formula_anonymous: str = Field(
+    formula_anonymous: Optional[str] = Field(
         None,
         title="Anonymous Formula",
         description="Anonymized representation of the formula (not including the working ion).",
@@ -242,7 +246,8 @@ class BaseElectrode(BaseModel):
     )
 
     # Make sure that the datetime field is properly formatted
-    @validator("last_updated", pre=True)
+    @field_validator("last_updated", mode="before")
+    @classmethod
     def last_updated_dict_ok(cls, v):
         return MontyDecoder().process_decoded(v)
 
@@ -252,26 +257,26 @@ class InsertionElectrodeDoc(InsertionVoltagePairDoc, BaseElectrode):
     Insertion electrode
     """
 
-    host_structure: Structure = Field(
+    host_structure: Optional[Structure] = Field(
         None, description="Host structure (structure without the working ion)."
     )
 
-    adj_pairs: List[InsertionVoltagePairDoc] = Field(
+    adj_pairs: Optional[List[InsertionVoltagePairDoc]] = Field(
         None, description="Returns all of the voltage steps material pairs."
     )
 
-    material_ids: List[MPID] = Field(
+    material_ids: Optional[List[MPID]] = Field(
         None,
         description="The ids of all structures that matched to the present host lattice, regardless of stability. "
         "The stable entries can be found in the adjacent pairs.",
     )
 
-    entries_composition_summary: EntriesCompositionSummary = Field(
+    entries_composition_summary: Optional[EntriesCompositionSummary] = Field(
         None,
         description="Composition summary data for all material in entries across all voltage pairs.",
     )
 
-    electrode_object: InsertionElectrode = Field(
+    electrode_object: Optional[InsertionElectrode] = Field(
         None, description="The Pymatgen electrode object."
     )
 
@@ -431,16 +436,16 @@ class ConversionElectrodeDoc(ConversionVoltagePairDoc, BaseElectrode):
     Conversion electrode
     """
 
-    initial_comp_formula: str = Field(
+    initial_comp_formula: Optional[str] = Field(
         None,
         description="The starting composition for the ConversionElectrode represented as a string/formula.",
     )
 
-    adj_pairs: List[ConversionVoltagePairDoc] = Field(
+    adj_pairs: Optional[List[ConversionVoltagePairDoc]] = Field(
         None, description="Returns all of the voltage steps material pairs."
     )
 
-    electrode_object: ConversionElectrode = Field(
+    electrode_object: Optional[ConversionElectrode] = Field(
         None, description="The Pymatgen conversion electrode object."
     )
 
diff --git a/emmet-core/emmet/core/electronic_structure.py b/emmet-core/emmet/core/electronic_structure.py
index d271325..54b38c2 100644
--- a/emmet-core/emmet/core/electronic_structure.py
+++ b/emmet-core/emmet/core/electronic_structure.py
@@ -46,7 +46,7 @@ class BSObjectDoc(BaseModel):
     Band object document.
     """
 
-    task_id: MPID = Field(
+    task_id: Optional[MPID] = Field(
         None,
         description="The source calculation (task) ID that this band structure comes from. "
         "This has the same form as a Materials Project ID.",
@@ -57,7 +57,7 @@ class BSObjectDoc(BaseModel):
         default_factory=datetime.utcnow,
     )
 
-    data: Union[Dict, BandStructureSymmLine] = Field(
+    data: Optional[Union[Dict, BandStructureSymmLine]] = Field(
         None, description="The band structure object for the given calculation ID"
     )
 
@@ -67,7 +67,7 @@ class DOSObjectDoc(BaseModel):
     DOS object document.
     """
 
-    task_id: MPID = Field(
+    task_id: Optional[MPID] = Field(
         None,
         description="The source calculation (task) ID that this density of states comes from. "
         "This has the same form as a Materials Project ID.",
@@ -78,7 +78,7 @@ class DOSObjectDoc(BaseModel):
         default_factory=datetime.utcnow,
     )
 
-    data: CompleteDos = Field(
+    data: Optional[CompleteDos] = Field(
         None, description="The density of states object for the given calculation ID."
     )
 
@@ -92,11 +92,15 @@ class ElectronicStructureBaseData(BaseModel):
 
     band_gap: float = Field(..., description="Band gap energy in eV.")
 
-    cbm: Union[float, Dict] = Field(None, description="Conduction band minimum data.")
+    cbm: Optional[Union[float, Dict]] = Field(
+        None, description="Conduction band minimum data."
+    )
 
-    vbm: Union[float, Dict] = Field(None, description="Valence band maximum data.")
+    vbm: Optional[Union[float, Dict]] = Field(
+        None, description="Valence band maximum data."
+    )
 
-    efermi: float = Field(None, description="Fermi energy in eV.")
+    efermi: Optional[float] = Field(None, description="Fermi energy in eV.")
 
 
 class ElectronicStructureSummary(ElectronicStructureBaseData):
@@ -120,53 +124,57 @@ class BandStructureSummaryData(ElectronicStructureSummary):
 
 
 class DosSummaryData(ElectronicStructureBaseData):
-    spin_polarization: float = Field(
+    spin_polarization: Optional[float] = Field(
         None, description="Spin polarization at the fermi level."
     )
 
 
 class BandstructureData(BaseModel):
-    setyawan_curtarolo: BandStructureSummaryData = Field(
+    setyawan_curtarolo: Optional[BandStructureSummaryData] = Field(
         None,
         description="Band structure summary data using the Setyawan-Curtarolo path convention.",
     )
 
-    hinuma: BandStructureSummaryData = Field(
+    hinuma: Optional[BandStructureSummaryData] = Field(
         None,
         description="Band structure summary data using the Hinuma et al. path convention.",
     )
 
-    latimer_munro: BandStructureSummaryData = Field(
+    latimer_munro: Optional[BandStructureSummaryData] = Field(
         None,
         description="Band structure summary data using the Latimer-Munro path convention.",
     )
 
 
 class DosData(BaseModel):
-    total: Dict[Union[Spin, str], DosSummaryData] = Field(
+    total: Optional[Dict[Union[Spin, str], DosSummaryData]] = Field(
         None, description="Total DOS summary data."
     )
 
-    elemental: Dict[
-        Element,
+    elemental: Optional[
         Dict[
-            Union[Literal["total", "s", "p", "d", "f"], OrbitalType],
-            Dict[Union[Literal["1", "-1"], Spin], DosSummaryData],
-        ],
+            Element,
+            Dict[
+                Union[Literal["total", "s", "p", "d", "f"], OrbitalType],
+                Dict[Union[Literal["1", "-1"], Spin], DosSummaryData],
+            ],
+        ]
     ] = Field(
         None,
         description="Band structure summary data using the Hinuma et al. path convention.",
     )
 
-    orbital: Dict[
-        Union[Literal["total", "s", "p", "d", "f"], OrbitalType],
-        Dict[Union[Literal["1", "-1"], Spin], DosSummaryData],
+    orbital: Optional[
+        Dict[
+            Union[Literal["total", "s", "p", "d", "f"], OrbitalType],
+            Dict[Union[Literal["1", "-1"], Spin], DosSummaryData],
+        ]
     ] = Field(
         None,
         description="Band structure summary data using the Latimer-Munro path convention.",
     )
 
-    magnetic_ordering: Union[str, Ordering] = Field(
+    magnetic_ordering: Optional[Union[Ordering, str]] = Field(
         None, description="Magnetic ordering of the calculation."
     )
 
@@ -179,13 +187,15 @@ class ElectronicStructureDoc(PropertyDoc, ElectronicStructureSummary):
     Definition for a core Electronic Structure Document
     """
 
-    property_name = "electronic_structure"
+    property_name: str = "electronic_structure"
 
-    bandstructure: BandstructureData = Field(
+    bandstructure: Optional[BandstructureData] = Field(
         None, description="Band structure data for the material."
     )
 
-    dos: DosData = Field(None, description="Density of states data for the material.")
+    dos: Optional[DosData] = Field(
+        None, description="Density of states data for the material."
+    )
 
     last_updated: datetime = Field(
         description="Timestamp for when this document was last updated.",
@@ -434,22 +444,22 @@ class ElectronicStructureDoc(PropertyDoc, ElectronicStructureSummary):
         new_origin_task_id = None
 
         if bs_gap is not None and bs_gap <= dos_gap + 0.2:
-            summary_task = bs_entry.setyawan_curtarolo.task_id
+            summary_task = bs_entry.setyawan_curtarolo.task_id  # type: ignore
             summary_band_gap = bs_gap
             summary_cbm = (
                 bs_entry.setyawan_curtarolo.cbm.get("energy", None)  # type: ignore
-                if bs_entry.setyawan_curtarolo.cbm is not None
+                if bs_entry.setyawan_curtarolo.cbm is not None  # type: ignore
                 else None
             )
             summary_vbm = (
                 bs_entry.setyawan_curtarolo.vbm.get("energy", None)  # type: ignore
-                if bs_entry.setyawan_curtarolo.cbm is not None
+                if bs_entry.setyawan_curtarolo.cbm is not None  # type: ignore
                 else None
             )  # type: ignore
-            summary_efermi = bs_entry.setyawan_curtarolo.efermi
-            is_gap_direct = bs_entry.setyawan_curtarolo.is_gap_direct
-            is_metal = bs_entry.setyawan_curtarolo.is_metal
-            summary_magnetic_ordering = bs_entry.setyawan_curtarolo.magnetic_ordering
+            summary_efermi = bs_entry.setyawan_curtarolo.efermi  # type: ignore
+            is_gap_direct = bs_entry.setyawan_curtarolo.is_gap_direct  # type: ignore
+            is_metal = bs_entry.setyawan_curtarolo.is_metal  # type: ignore
+            summary_magnetic_ordering = bs_entry.setyawan_curtarolo.magnetic_ordering  # type: ignore
 
             for origin in origins:
                 if origin["name"] == "setyawan_curtarolo":
@@ -457,7 +467,7 @@ class ElectronicStructureDoc(PropertyDoc, ElectronicStructureSummary):
                     new_origin_task_id = origin["task_id"]
 
         else:
-            summary_task = dos_entry.dict()["total"][Spin.up]["task_id"]
+            summary_task = dos_entry.model_dump()["total"][Spin.up]["task_id"]
             summary_band_gap = dos_gap
             summary_cbm = dos_cbm
             summary_vbm = dos_vbm
diff --git a/emmet-core/emmet/core/eos.py b/emmet-core/emmet/core/eos.py
index e33616b..b084b45 100644
--- a/emmet-core/emmet/core/eos.py
+++ b/emmet-core/emmet/core/eos.py
@@ -1,4 +1,4 @@
-from typing import Dict, List
+from typing import Dict, List, Optional
 
 from pydantic import BaseModel, Field
 
@@ -8,22 +8,22 @@ class EOSDoc(BaseModel):
     Fitted equations of state and energies and volumes used for fits.
     """
 
-    energies: List[float] = Field(
+    energies: Optional[List[float]] = Field(
         None,
         description="Common energies in eV/atom that the equations of state are plotted with.",
     )
 
-    volumes: List[float] = Field(
+    volumes: Optional[List[float]] = Field(
         None,
         description="Common volumes in A³/atom that the equations of state are plotted with.",
     )
 
-    eos: Dict = Field(
+    eos: Optional[Dict] = Field(
         None,
         description="Data for each type of equation of state.",
     )
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The Materials Project ID of the material. This comes in the form: mp-******.",
     )
diff --git a/emmet-core/emmet/core/feff/task.py b/emmet-core/emmet/core/feff/task.py
index efca08d..ab9881a 100644
--- a/emmet-core/emmet/core/feff/task.py
+++ b/emmet-core/emmet/core/feff/task.py
@@ -27,7 +27,7 @@ class CalcType(ValueEnum):
 class TaskDocument(BaseTaskDocument, StructureMetadata):
     """Task Document for a FEFF XAS Calculation. Doesn't support EELS for now"""
 
-    calc_code = "FEFF"
+    calc_code: str = "FEFF"
 
     structure: Structure
     input_parameters: Dict[str, Any] = Field(
diff --git a/emmet-core/emmet/core/fermi.py b/emmet-core/emmet/core/fermi.py
index c88a871..b3e8d94 100644
--- a/emmet-core/emmet/core/fermi.py
+++ b/emmet-core/emmet/core/fermi.py
@@ -1,7 +1,7 @@
-from typing import List
+from typing import List, Optional
 from datetime import datetime
 from monty.json import MontyDecoder
-from pydantic import BaseModel, Field, validator
+from pydantic import field_validator, BaseModel, Field
 
 
 class FermiDoc(BaseModel):
@@ -9,28 +9,29 @@ class FermiDoc(BaseModel):
     Fermi surfaces.
     """
 
-    fermi_surfaces: List[dict] = Field(
+    fermi_surfaces: Optional[List[dict]] = Field(
         None,
         description="List of IFermi FermiSurface objects.",
     )
 
-    surface_types: List[str] = Field(
+    surface_types: Optional[List[str]] = Field(
         None,
         description="Type of each fermi surface in the fermi_surfaces list.\
             Is either CBM or VBM for semiconductors, or fermi_surface for metals.",
     )
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The Materials Project ID of the material. This comes in the form: mp-******.",
     )
 
-    last_updated: datetime = Field(
+    last_updated: Optional[datetime] = Field(
         None,
         description="Timestamp for the most recent calculation for this fermi surface document.",
     )
 
     # Make sure that the datetime field is properly formatted
-    @validator("last_updated", pre=True)
+    @field_validator("last_updated", mode="before")
+    @classmethod
     def last_updated_dict_ok(cls, v):
         return MontyDecoder().process_decoded(v)
diff --git a/emmet-core/emmet/core/find_structure.py b/emmet-core/emmet/core/find_structure.py
index 19a5c10..bf8d6be 100644
--- a/emmet-core/emmet/core/find_structure.py
+++ b/emmet-core/emmet/core/find_structure.py
@@ -1,5 +1,6 @@
 from emmet.core.mpid import MPID, MPculeID
 from pydantic import Field, BaseModel
+from typing import Optional
 
 
 class FindStructure(BaseModel):
@@ -7,16 +8,16 @@ class FindStructure(BaseModel):
     Class defining find structure return data
     """
 
-    material_id: MPID = Field(
+    material_id: Optional[MPID] = Field(
         None,
         description="The ID of this material, used as a universal reference across property documents."
         "This comes in the form: mp-******.",
     )
-    normalized_rms_displacement: float = Field(
+    normalized_rms_displacement: Optional[float] = Field(
         None,
         description="Volume normalized root-mean squared displacement between the structures",
     )
-    max_distance_paired_sites: float = Field(
+    max_distance_paired_sites: Optional[float] = Field(
         None,
         description="Maximum distance between paired sites.",
     )
@@ -27,11 +28,11 @@ class FindMolecule(BaseModel):
     Class defining find molecule return data
     """
 
-    molecule_id: MPculeID = Field(
+    molecule_id: Optional[MPculeID] = Field(
         None,
         description="The ID of this molecule, used as a universal reference across property documents.",
     )
-    rmsd: float = Field(
+    rmsd: Optional[float] = Field(
         None,
         description="Root-mean-squared displacement of the molecule compared to a reference",
     )
diff --git a/emmet-core/emmet/core/formula_autocomplete.py b/emmet-core/emmet/core/formula_autocomplete.py
index 176526e..94f54d9 100644
--- a/emmet-core/emmet/core/formula_autocomplete.py
+++ b/emmet-core/emmet/core/formula_autocomplete.py
@@ -1,4 +1,5 @@
 from pydantic import Field, BaseModel
+from typing import Optional
 
 
 class FormulaAutocomplete(BaseModel):
@@ -6,7 +7,7 @@ class FormulaAutocomplete(BaseModel):
     Class defining formula autocomplete return data
     """
 
-    formula_pretty: str = Field(
+    formula_pretty: Optional[str] = Field(
         None,
         description="Human readable chemical formula.",
     )
diff --git a/emmet-core/emmet/core/grain_boundary.py b/emmet-core/emmet/core/grain_boundary.py
index 42ff9de..141a5a4 100644
--- a/emmet-core/emmet/core/grain_boundary.py
+++ b/emmet-core/emmet/core/grain_boundary.py
@@ -1,5 +1,5 @@
-from typing import List
-from pydantic import BaseModel, Field, validator
+from typing import List, Optional
+from pydantic import field_validator, BaseModel, Field
 from enum import Enum
 from datetime import datetime
 from monty.json import MontyDecoder
@@ -21,65 +21,68 @@ class GrainBoundaryDoc(BaseModel):
     Grain boundary energies, work of separation...
     """
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The Materials Project ID of the material. This comes in the form: mp-******.",
     )
 
-    sigma: int = Field(
+    sigma: Optional[int] = Field(
         None,
         description="Sigma value of the boundary.",
     )
 
-    type: GBTypeEnum = Field(
+    type: Optional[GBTypeEnum] = Field(
         None,
         description="Grain boundary type.",
     )
 
-    rotation_axis: List[int] = Field(
+    rotation_axis: Optional[List[int]] = Field(
         None,
         description="Rotation axis.",
     )
 
-    gb_plane: List[int] = Field(
+    gb_plane: Optional[List[int]] = Field(
         None,
         description="Grain boundary plane.",
     )
 
-    rotation_angle: float = Field(
+    rotation_angle: Optional[float] = Field(
         None,
         description="Rotation angle in degrees.",
     )
 
-    gb_energy: float = Field(
+    gb_energy: Optional[float] = Field(
         None,
         description="Grain boundary energy in J/m^2.",
     )
 
-    initial_structure: GrainBoundary = Field(
+    initial_structure: Optional[GrainBoundary] = Field(
         None, description="Initial grain boundary structure."
     )
 
-    final_structure: GrainBoundary = Field(
+    final_structure: Optional[GrainBoundary] = Field(
         None, description="Final grain boundary structure."
     )
 
-    pretty_formula: str = Field(None, description="Reduced formula of the material.")
+    pretty_formula: Optional[str] = Field(
+        None, description="Reduced formula of the material."
+    )
 
-    w_sep: float = Field(None, description="Work of separation in J/m^2.")
+    w_sep: Optional[float] = Field(None, description="Work of separation in J/m^2.")
 
-    cif: str = Field(None, description="CIF file of the structure.")
+    cif: Optional[str] = Field(None, description="CIF file of the structure.")
 
-    chemsys: str = Field(
+    chemsys: Optional[str] = Field(
         None, description="Dash-delimited string of elements in the material."
     )
 
-    last_updated: datetime = Field(
+    last_updated: Optional[datetime] = Field(
         None,
         description="Timestamp for the most recent calculation for this Material document.",
     )
 
     # Make sure that the datetime field is properly formatted
-    @validator("last_updated", pre=True)
+    @field_validator("last_updated", mode="before")
+    @classmethod
     def last_updated_dict_ok(cls, v):
         return MontyDecoder().process_decoded(v)
diff --git a/emmet-core/emmet/core/magnetism.py b/emmet-core/emmet/core/magnetism.py
index 3fc732c..ba1070e 100644
--- a/emmet-core/emmet/core/magnetism.py
+++ b/emmet-core/emmet/core/magnetism.py
@@ -1,4 +1,4 @@
-from typing import List
+from typing import List, Optional
 
 from pydantic import Field
 from pymatgen.core import Structure
@@ -13,54 +13,54 @@ class MagnetismDoc(PropertyDoc):
     Magnetic data obtain from the calculated structure
     """
 
-    property_name = "magnetism"
+    property_name: str = "magnetism"
 
-    ordering: str = Field(
+    ordering: Optional[str] = Field(
         None,
         description="Magnetic ordering.",
     )
 
-    is_magnetic: bool = Field(
+    is_magnetic: Optional[bool] = Field(
         None,
         description="Whether the material is magnetic.",
     )
 
-    exchange_symmetry: int = Field(
+    exchange_symmetry: Optional[int] = Field(
         None,
         description="Exchange symmetry.",
     )
 
-    num_magnetic_sites: int = Field(
+    num_magnetic_sites: Optional[int] = Field(
         None,
         description="The number of magnetic sites.",
     )
 
-    num_unique_magnetic_sites: int = Field(
+    num_unique_magnetic_sites: Optional[int] = Field(
         None,
         description="The number of unique magnetic sites.",
     )
 
-    types_of_magnetic_species: List[str] = Field(
+    types_of_magnetic_species: Optional[List[str]] = Field(
         None,
         description="Magnetic specie elements.",
     )
 
-    magmoms: List[float] = Field(
+    magmoms: Optional[List[float]] = Field(
         None,
         description="Magnetic moments for each site.",
     )
 
-    total_magnetization: float = Field(
+    total_magnetization: Optional[float] = Field(
         None,
         description="Total magnetization in μB.",
     )
 
-    total_magnetization_normalized_vol: float = Field(
+    total_magnetization_normalized_vol: Optional[float] = Field(
         None,
         description="Total magnetization normalized by volume in μB/Å³.",
     )
 
-    total_magnetization_normalized_formula_units: float = Field(
+    total_magnetization_normalized_formula_units: Optional[float] = Field(
         None,
         description="Total magnetization normalized by formula unit in μB/f.u. .",
     )
diff --git a/emmet-core/emmet/core/material.py b/emmet-core/emmet/core/material.py
index 3641395..57872b4 100644
--- a/emmet-core/emmet/core/material.py
+++ b/emmet-core/emmet/core/material.py
@@ -2,7 +2,7 @@
 from __future__ import annotations
 
 from datetime import datetime
-from typing import List, Mapping, Type, TypeVar, Union
+from typing import List, Mapping, Type, TypeVar, Union, Optional
 
 from pydantic import BaseModel, Field
 
@@ -55,7 +55,7 @@ class MaterialsDoc(StructureMetadata):
         description="Whether this materials document is deprecated.",
     )
 
-    deprecation_reasons: List[Union[DeprecationMessage, str]] = Field(
+    deprecation_reasons: Optional[List[Union[DeprecationMessage, str]]] = Field(
         None,
         description="List of deprecation tags detailing why this materials document isn't valid.",
     )
@@ -72,7 +72,7 @@ class MaterialsDoc(StructureMetadata):
 
     deprecated_tasks: List[str] = Field([], title="Deprecated Tasks")
 
-    calc_types: Mapping[str, str] = Field(
+    calc_types: Optional[Mapping[str, str]] = Field(
         None,
         description="Calculation types for all the calculations that make up this material.",
     )
@@ -87,7 +87,7 @@ class MaterialsDoc(StructureMetadata):
         default_factory=datetime.utcnow,
     )
 
-    origins: List[PropertyOrigin] = Field(
+    origins: Optional[List[PropertyOrigin]] = Field(
         None, description="Dictionary for tracking the provenance of properties."
     )
 
@@ -132,7 +132,7 @@ class CoreMoleculeDoc(MoleculeMetadata):
     )
 
     # TODO: Why might a molecule be deprecated?
-    deprecation_reasons: List[str] = Field(
+    deprecation_reasons: Optional[List[str]] = Field(
         None,
         description="List of deprecation tags detailing why this molecules document isn't valid",
     )
@@ -151,7 +151,7 @@ class CoreMoleculeDoc(MoleculeMetadata):
     # TODO: Should this be MPID?
     deprecated_tasks: List[str] = Field([], title="Deprecated Tasks")
 
-    calc_types: Mapping[str, str] = Field(
+    calc_types: Optional[Mapping[str, str]] = Field(
         None,
         description="Calculation types for all the tasks that make up this molecule",
     )
@@ -166,7 +166,7 @@ class CoreMoleculeDoc(MoleculeMetadata):
         default_factory=datetime.utcnow,
     )
 
-    origins: List[PropertyOrigin] = Field(
+    origins: Optional[List[PropertyOrigin]] = Field(
         None, description="Dictionary for tracking the provenance of properties"
     )
 
diff --git a/emmet-core/emmet/core/material_property.py b/emmet-core/emmet/core/material_property.py
index 4665254..068ee79 100644
--- a/emmet-core/emmet/core/material_property.py
+++ b/emmet-core/emmet/core/material_property.py
@@ -2,7 +2,7 @@
 from __future__ import annotations
 
 from datetime import datetime
-from typing import Sequence, Type, TypeVar, Union, List
+from typing import Sequence, Type, TypeVar, Union, List, Optional
 
 from pydantic import Field
 from pymatgen.core import Structure
@@ -34,7 +34,7 @@ class PropertyDoc(StructureMetadata):
         description="Whether this property document is deprecated.",
     )
 
-    deprecation_reasons: List[Union[DeprecationMessage, str]] = Field(
+    deprecation_reasons: Optional[List[Union[DeprecationMessage, str]]] = Field(
         None,
         description="List of deprecation tags detailing why this document isn't valid.",
     )
diff --git a/emmet-core/emmet/core/ml.py b/emmet-core/emmet/core/ml.py
index 09d8b64..fabfd23 100644
--- a/emmet-core/emmet/core/ml.py
+++ b/emmet-core/emmet/core/ml.py
@@ -51,47 +51,51 @@ class MLDoc(ElasticityDoc):
         - youngs_modulus (float): Young's modulus
     """
 
-    property_name = "ml"
+    property_name: str = "ml"
 
     # metadata
     structure: Structure = Field(description="Original structure")
-    matcalc_version: str = Field(
+    matcalc_version: Optional[str] = Field(
         None, description="Version of matcalc used to generate this document"
     )
-    model_name: str = Field(None, description="Name of model used as ML potential.")
-    model_version: str = Field(
+    model_name: Optional[str] = Field(
+        None, description="Name of model used as ML potential."
+    )
+    model_version: Optional[str] = Field(
         None, description="Version of model used as ML potential"
     )
 
     # relaxation attributes
-    final_structure: Structure = Field(
+    final_structure: Optional[Structure] = Field(
         None, description="ML-potential-relaxed structure"
     )
-    energy: float = Field(None, description="Final energy in eV")
-    volume: float = Field(None, description="Final volume in Angstrom^3")
-    a: float = Field(None, description="Lattice length a in Angstrom")
-    b: float = Field(None, description="Lattice length b in Angstrom")
-    c: float = Field(None, description="Lattice length c in Angstrom")
-    alpha: float = Field(None, description="Lattice angle alpha in degrees")
-    beta: float = Field(None, description="Lattice angle beta in degrees")
-    gamma: float = Field(None, description="Lattice angle gamma in degrees")
+    energy: Optional[float] = Field(None, description="Final energy in eV")
+    volume: Optional[float] = Field(None, description="Final volume in Angstrom^3")
+    a: Optional[float] = Field(None, description="Lattice length a in Angstrom")
+    b: Optional[float] = Field(None, description="Lattice length b in Angstrom")
+    c: Optional[float] = Field(None, description="Lattice length c in Angstrom")
+    alpha: Optional[float] = Field(None, description="Lattice angle alpha in degrees")
+    beta: Optional[float] = Field(None, description="Lattice angle beta in degrees")
+    gamma: Optional[float] = Field(None, description="Lattice angle gamma in degrees")
 
     # equation of state attributes
-    eos: Dict[str, List[float]] = Field(
+    eos: Optional[Dict[str, List[float]]] = Field(
         None, description="dict with keys energies and volumes"
     )
-    bulk_modulus_bm: float = Field(None, description="bm.b0_GPa")
+    bulk_modulus_bm: Optional[float] = Field(None, description="bm.b0_GPa")
 
     # phonons attributes
-    temperatures: List[float] = Field(None, description="list of temperatures")
-    free_energy: List[float] = Field(
+    temperatures: Optional[List[float]] = Field(
+        None, description="list of temperatures"
+    )
+    free_energy: Optional[List[float]] = Field(
         None,
         description="list of Helmholtz free energies at corresponding temperatures",
     )
-    entropy: List[float] = Field(
+    entropy: Optional[List[float]] = Field(
         None, description="list of entropies at corresponding temperatures in eV/K"
     )
-    heat_capacity: List[float] = Field(
+    heat_capacity: Optional[List[float]] = Field(
         None,
         description="list of heat capacities at constant volume at corresponding "
         "temperatures in eV/K",
diff --git a/emmet-core/emmet/core/mobility/migrationgraph.py b/emmet-core/emmet/core/mobility/migrationgraph.py
index 9e38103..ad96850 100644
--- a/emmet-core/emmet/core/mobility/migrationgraph.py
+++ b/emmet-core/emmet/core/mobility/migrationgraph.py
@@ -1,5 +1,5 @@
 from datetime import datetime
-from typing import List, Union, Dict, Tuple, Sequence
+from typing import List, Union, Dict, Tuple, Sequence, Optional
 
 from pydantic import Field
 import numpy as np
@@ -29,7 +29,7 @@ class MigrationGraphDoc(EmmetBaseModel):
         ..., description="The battery id for this MigrationGraphDoc"
     )
 
-    last_updated: datetime = Field(
+    last_updated: Optional[datetime] = Field(
         None,
         description="Timestamp for the most recent calculation for this MigrationGraph document.",
     )
@@ -43,21 +43,21 @@ class MigrationGraphDoc(EmmetBaseModel):
         description="Indicates whether a migration graph fails to be constructed from the provided entries. Defaults to False, indicating mg can be constructed from entries.",  # noqa: E501
     )
 
-    hop_cutoff: float = Field(
+    hop_cutoff: Optional[float] = Field(
         None,
         description="The numerical value in angstroms used to cap the maximum length of a hop.",
     )
 
-    entries_for_generation: List[ComputedStructureEntry] = Field(
+    entries_for_generation: Optional[List[ComputedStructureEntry]] = Field(
         None,
         description="A list of ComputedStructureEntries used to generate the structure with all working ion sites.",
     )
 
-    working_ion_entry: Union[ComputedEntry, ComputedStructureEntry] = Field(
+    working_ion_entry: Optional[Union[ComputedEntry, ComputedStructureEntry]] = Field(
         None, description="The ComputedStructureEntry of the working ion."
     )
 
-    migration_graph: MigrationGraph = Field(
+    migration_graph: Optional[MigrationGraph] = Field(
         None,
         description="The MigrationGraph object as defined in pymatgen.analysis.diffusion.",
     )
@@ -67,32 +67,34 @@ class MigrationGraphDoc(EmmetBaseModel):
         description="Flag indicating whether this document has populated the supercell fields",
     )
 
-    min_length_sc: float = Field(
+    min_length_sc: Optional[float] = Field(
         None,
         description="The minimum length used to generate supercell using pymatgen.",
     )
 
-    minmax_num_atoms: Tuple[int, int] = Field(
+    minmax_num_atoms: Optional[Tuple[int, int]] = Field(
         None,
         description="The min/max number of atoms used to genreate supercell using pymatgen.",
     )
 
-    matrix_supercell_structure: Structure = Field(
+    matrix_supercell_structure: Optional[Structure] = Field(
         None,
         description="The matrix suprcell structure that does not contain the mobile ions for the purpose of migration analysis.",  # noqa: E501
     )
 
-    conversion_matrix: List[List[Union[int, float]]] = Field(
+    conversion_matrix: Optional[List[List[Union[int, float]]]] = Field(
         None,
         description="The conversion matrix used to convert unit cell to supercell.",
     )
 
-    inserted_ion_coords: List[Dict[str, Union[List[float], str, int]]] = Field(
+    inserted_ion_coords: Optional[
+        List[Dict[str, Union[List[float], str, int]]]
+    ] = Field(
         None,
         description="A dictionary containing all mobile ion fractional coordinates in terms of supercell.",
     )
 
-    insert_coords_combo: List[str] = Field(
+    insert_coords_combo: Optional[List[str]] = Field(
         None,
         description="A list of combinations 'a+b' to designate hops in the supercell. Each combo should correspond to one unique hop in MigrationGraph.",  # noqa: E501
     )
diff --git a/emmet-core/emmet/core/molecules/atomic.py b/emmet-core/emmet/core/molecules/atomic.py
index 42d26dc..9e0896a 100644
--- a/emmet-core/emmet/core/molecules/atomic.py
+++ b/emmet-core/emmet/core/molecules/atomic.py
@@ -18,7 +18,7 @@ SPINS_METHODS = ["nbo", "mulliken"]
 class PartialChargesDoc(PropertyDoc):
     """Atomic partial charges of a molecule"""
 
-    property_name = "partial_charges"
+    property_name: str = "partial_charges"
 
     method: str = Field(
         ..., description="Method used to compute atomic partial charges"
@@ -107,7 +107,7 @@ class PartialChargesDoc(PropertyDoc):
 class PartialSpinsDoc(PropertyDoc):
     """Atomic partial charges of a molecule"""
 
-    property_name = "partial_spins"
+    property_name: str = "partial_spins"
 
     method: str = Field(..., description="Method used to compute atomic partial spins")
 
diff --git a/emmet-core/emmet/core/molecules/bonds.py b/emmet-core/emmet/core/molecules/bonds.py
index 3e73f17..5706eca 100644
--- a/emmet-core/emmet/core/molecules/bonds.py
+++ b/emmet-core/emmet/core/molecules/bonds.py
@@ -337,7 +337,7 @@ def nbo_molecule_graph(mol: Molecule, nbo: Dict[str, Any]):
 class MoleculeBondingDoc(PropertyDoc):
     """Representation of molecular bonding."""
 
-    property_name = "bonding"
+    property_name: str = "bonding"
 
     molecule_graph: MoleculeGraph = Field(..., description="Molecule graph")
 
diff --git a/emmet-core/emmet/core/molecules/metal_binding.py b/emmet-core/emmet/core/molecules/metal_binding.py
index cd78b5b..b530cd4 100644
--- a/emmet-core/emmet/core/molecules/metal_binding.py
+++ b/emmet-core/emmet/core/molecules/metal_binding.py
@@ -34,44 +34,46 @@ class MetalBindingData(BaseModel):
         ..., description="The MPculeID of the molecule with the metal atom/ion removed"
     )
 
-    metal_index: int = Field(
+    metal_index: Optional[int] = Field(
         None,
         description="Index of the metal in this Molecule (in case of a molecule with multiple identical "
         "metal atoms/ions)",
     )
 
-    metal_element: Union[str, Species, Element] = Field(
+    metal_element: Optional[Union[str, Species, Element]] = Field(
         None, description="The metal bound to the molecule"
     )
 
-    metal_partial_charge: float = Field(
+    metal_partial_charge: Optional[float] = Field(
         None, description="The exact calculated partial charge of the metal"
     )
 
-    metal_partial_spin: float = Field(
+    metal_partial_spin: Optional[float] = Field(
         None, description="The exact calculated partial spin on the metal"
     )
 
-    metal_assigned_charge: float = Field(
+    metal_assigned_charge: Optional[float] = Field(
         None,
         description="The integral charge assigned to this metal based on partial charge/spin data",
     )
 
-    metal_assigned_spin: float = Field(
+    metal_assigned_spin: Optional[float] = Field(
         None,
         description="The integral spin multiplicity assigned to this metal based on partial spin data",
     )
 
-    number_coordinate_bonds: int = Field(
+    number_coordinate_bonds: Optional[int] = Field(
         None,
         description="The number of atoms neighboring the metal atom or ion of interest",
     )
 
-    coordinating_atoms: List[Union[str, Species]] = Field(
+    coordinating_atoms: Optional[List[Union[str, Species]]] = Field(
         None, description="The elements/species coordinating the metal."
     )
 
-    coordinate_bond_lengths: Dict[str, Dict[str, Union[float, List[float]]]] = Field(
+    coordinate_bond_lengths: Optional[
+        Dict[str, Dict[str, Union[float, List[float]]]]
+    ] = Field(
         None,
         description="Bond lengths and statistics broken down by the coordinating atoms",
     )
@@ -92,12 +94,12 @@ class MetalBindingData(BaseModel):
         None, description="The free energy change (∆G) of binding (units: eV)"
     )
 
-    metal_thermo_property_id: str = Field(
+    metal_thermo_property_id: Optional[str] = Field(
         None,
         description="ID of MoleculeThermoDoc used to obtain the thermochemistry of the metal atom/ion",
     )
 
-    nometal_thermo_property_id: str = Field(
+    nometal_thermo_property_id: Optional[str] = Field(
         None,
         description="ID of MoleculeThermoDoc used to obtain the thermochemistry of of the molecule with the "
         "metal atom/ion removed",
@@ -115,75 +117,75 @@ class MetalBindingData(BaseModel):
 class MetalBindingDoc(PropertyDoc):
     """Metal binding properties of a molecule"""
 
-    property_name = "metal_binding"
+    property_name: str = "metal_binding"
 
     method: str = Field(
         ...,
         description="Method used to determine the charge, spin, and coordination environment of a metal",
     )
 
-    binding_partial_charges_property_id: str = Field(
+    binding_partial_charges_property_id: Optional[str] = Field(
         None,
         description="ID of PartialChargesDoc used to estimate metal charge",
     )
 
-    binding_partial_spins_property_id: str = Field(
+    binding_partial_spins_property_id: Optional[str] = Field(
         None,
         description="ID of PartialSpinsDoc used to estimate metal spin",
     )
 
-    binding_partial_charges_lot_solvent: str = Field(
+    binding_partial_charges_lot_solvent: Optional[str] = Field(
         None,
         description="Combination of level of theory and solvent used to calculate atomic partial charges",
     )
 
-    binding_partial_spins_lot_solvent: str = Field(
+    binding_partial_spins_lot_solvent: Optional[str] = Field(
         None,
         description="Combination of level of theory and solvent used to calculate atomic partial spins",
     )
 
-    binding_charge_spin_method: str = Field(
+    binding_charge_spin_method: Optional[str] = Field(
         None,
         description="The method used for partial charges and spins (must be the same).",
     )
 
-    binding_bonding_property_id: str = Field(
+    binding_bonding_property_id: Optional[str] = Field(
         None,
         description="ID of MoleculeBondingDoc used to detect bonding in this molecule",
     )
 
-    binding_bonding_lot_solvent: str = Field(
+    binding_bonding_lot_solvent: Optional[str] = Field(
         None,
         description="Combination of level of theory and solvent used to determine the coordination environment "
         "of the metal atom or ion",
     )
 
-    binding_bonding_method: str = Field(
+    binding_bonding_method: Optional[str] = Field(
         None, description="The method used for to define bonding."
     )
 
-    binding_thermo_property_id: str = Field(
+    binding_thermo_property_id: Optional[str] = Field(
         None,
         description="ID of MoleculeThermoDoc used to obtain this molecule's thermochemistry",
     )
 
-    binding_thermo_lot_solvent: str = Field(
+    binding_thermo_lot_solvent: Optional[str] = Field(
         None,
         description="Combination of level of theory and solvent used for uncorrected thermochemistry",
     )
 
-    binding_thermo_correction_lot_solvent: str = Field(
+    binding_thermo_correction_lot_solvent: Optional[str] = Field(
         None,
         description="Combination of level of theory and solvent used to correct the electronic energy",
     )
 
-    binding_thermo_combined_lot_solvent: str = Field(
+    binding_thermo_combined_lot_solvent: Optional[str] = Field(
         None,
         descrption="Combination of level of theory and solvent used for molecular thermochemistry, combining "
         "both the frequency calculation and (potentially) the single-point energy correction.",
     )
 
-    binding_data: List[MetalBindingData] = Field(
+    binding_data: Optional[List[MetalBindingData]] = Field(
         None, description="Binding data for each metal atom or ion in the molecule"
     )
 
diff --git a/emmet-core/emmet/core/molecules/molecule_property.py b/emmet-core/emmet/core/molecules/molecule_property.py
index 860a4d9..19da450 100644
--- a/emmet-core/emmet/core/molecules/molecule_property.py
+++ b/emmet-core/emmet/core/molecules/molecule_property.py
@@ -2,7 +2,7 @@
 from __future__ import annotations
 
 from datetime import datetime
-from typing import Sequence, Type, TypeVar, List
+from typing import Sequence, Type, TypeVar, List, Optional
 
 from pydantic import Field
 from pymatgen.core.structure import Molecule
@@ -43,22 +43,22 @@ class PropertyDoc(MoleculeMetadata):
         description="Whether this property document is deprecated.",
     )
 
-    deprecation_reasons: List[str] = Field(
+    deprecation_reasons: Optional[List[str]] = Field(
         None,
         description="List of deprecation tags detailing why this document isn't valid",
     )
 
-    level_of_theory: LevelOfTheory = Field(
+    level_of_theory: Optional[LevelOfTheory] = Field(
         None, description="Level of theory used to generate this property document."
     )
 
-    solvent: str = Field(
+    solvent: Optional[str] = Field(
         None,
         description="String representation of the solvent "
         "environment used to generate this property document.",
     )
 
-    lot_solvent: str = Field(
+    lot_solvent: Optional[str] = Field(
         None,
         description="String representation of the level of theory and solvent "
         "environment used to generate this property document.",
diff --git a/emmet-core/emmet/core/molecules/orbitals.py b/emmet-core/emmet/core/molecules/orbitals.py
index c2cd311..c04d696 100644
--- a/emmet-core/emmet/core/molecules/orbitals.py
+++ b/emmet-core/emmet/core/molecules/orbitals.py
@@ -217,7 +217,7 @@ class Interaction(MSONable):
 
 
 class OrbitalDoc(PropertyDoc):
-    property_name = "natural bonding orbitals"
+    property_name: str = "natural bonding orbitals"
 
     # Always populated - closed-shell and open-shell
     open_shell: bool = Field(
@@ -229,49 +229,49 @@ class OrbitalDoc(PropertyDoc):
     )
 
     # Populated for closed-shell molecules
-    nbo_lone_pairs: List[LonePair] = Field(
+    nbo_lone_pairs: Optional[List[LonePair]] = Field(
         None, description="Lone pair orbitals of a closed-shell molecule"
     )
 
-    nbo_bonds: List[Bond] = Field(
+    nbo_bonds: Optional[List[Bond]] = Field(
         None, description="Bond-like orbitals of a closed-shell molecule"
     )
 
-    nbo_interactions: List[Interaction] = Field(
+    nbo_interactions: Optional[List[Interaction]] = Field(
         None, description="Orbital-orbital interactions of a closed-shell molecule"
     )
 
     # Populated for open-shell molecules
-    alpha_population: List[NaturalPopulation] = Field(
+    alpha_population: Optional[List[NaturalPopulation]] = Field(
         None,
         description="Natural electron populations of the alpha electrons of an "
         "open-shell molecule",
     )
-    beta_population: List[NaturalPopulation] = Field(
+    beta_population: Optional[List[NaturalPopulation]] = Field(
         None,
         description="Natural electron populations of the beta electrons of an "
         "open-shell molecule",
     )
 
-    alpha_lone_pairs: List[LonePair] = Field(
+    alpha_lone_pairs: Optional[List[LonePair]] = Field(
         None, description="Alpha electron lone pair orbitals of an open-shell molecule"
     )
-    beta_lone_pairs: List[LonePair] = Field(
+    beta_lone_pairs: Optional[List[LonePair]] = Field(
         None, description="Beta electron lone pair orbitals of an open-shell molecule"
     )
 
-    alpha_bonds: List[Bond] = Field(
+    alpha_bonds: Optional[List[Bond]] = Field(
         None, description="Alpha electron bond-like orbitals of an open-shell molecule"
     )
-    beta_bonds: List[Bond] = Field(
+    beta_bonds: Optional[List[Bond]] = Field(
         None, description="Beta electron bond-like orbitals of an open-shell molecule"
     )
 
-    alpha_interactions: List[Interaction] = Field(
+    alpha_interactions: Optional[List[Interaction]] = Field(
         None,
         description="Alpha electron orbital-orbital interactions of an open-shell molecule",
     )
-    beta_interactions: List[Interaction] = Field(
+    beta_interactions: Optional[List[Interaction]] = Field(
         None,
         description="Beta electron orbital-orbital interactions of an open-shell molecule",
     )
diff --git a/emmet-core/emmet/core/molecules/redox.py b/emmet-core/emmet/core/molecules/redox.py
index 3d67af8..3e973e3 100644
--- a/emmet-core/emmet/core/molecules/redox.py
+++ b/emmet-core/emmet/core/molecules/redox.py
@@ -27,69 +27,69 @@ class RedoxDoc(PropertyDoc):
     and oxidation potentials
     """
 
-    property_name = "redox"
+    property_name: str = "redox"
 
     base_property_id: str = Field(
         description="Property ID for the thermodynamic data of the " "base molecule"
     )
 
-    electron_affinity: float = Field(
+    electron_affinity: Optional[float] = Field(
         None, description="Vertical electron affinity (units: eV)"
     )
 
-    ea_task_id: MPID = Field(
+    ea_task_id: Optional[MPID] = Field(
         None, description="Task ID for the electron affinity calculation"
     )
 
-    ionization_energy: float = Field(
+    ionization_energy: Optional[float] = Field(
         None, description="Vertical ionization energy (units: eV)"
     )
 
-    ie_task_id: MPID = Field(
+    ie_task_id: Optional[MPID] = Field(
         None, description="Task ID for the ionization energy calculation"
     )
 
-    reduction_energy: float = Field(
+    reduction_energy: Optional[float] = Field(
         None, description="Adiabatic electronic energy of reduction (units: eV)"
     )
 
-    reduction_free_energy: float = Field(
+    reduction_free_energy: Optional[float] = Field(
         None, description="Adiabatic free energy of reduction (units: eV)"
     )
 
-    red_molecule_id: MPculeID = Field(
+    red_molecule_id: Optional[MPculeID] = Field(
         None, description="Molecule ID for adiabatic reduction"
     )
 
-    red_property_id: str = Field(
+    red_property_id: Optional[str] = Field(
         None,
         description="Property ID for the thermodynamic data of the " "reduced molecule",
     )
 
-    oxidation_energy: float = Field(
+    oxidation_energy: Optional[float] = Field(
         None, description="Adiabatic electronic energy of oxidation (units: eV)"
     )
 
-    oxidation_free_energy: float = Field(
+    oxidation_free_energy: Optional[float] = Field(
         None, description="Adiabatic free energy of oxidation (units: eV)"
     )
 
-    ox_molecule_id: MPculeID = Field(
+    ox_molecule_id: Optional[MPculeID] = Field(
         None, description="Molecule ID for adiabatic oxidation"
     )
 
-    ox_property_id: str = Field(
+    ox_property_id: Optional[str] = Field(
         None,
         description="Property ID for the thermodynamic data of the "
         "oxidized molecule",
     )
 
-    reduction_potential: float = Field(
+    reduction_potential: Optional[float] = Field(
         None,
         description="Reduction potential referenced to the standard hydrogen electrode (SHE) (units: V)",
     )
 
-    oxidation_potential: float = Field(
+    oxidation_potential: Optional[float] = Field(
         None,
         description="Oxidation potential referenced to the standard hydrogen electrode (SHE) (units: V)",
     )
diff --git a/emmet-core/emmet/core/molecules/summary.py b/emmet-core/emmet/core/molecules/summary.py
index 8cde772..0e5a020 100644
--- a/emmet-core/emmet/core/molecules/summary.py
+++ b/emmet-core/emmet/core/molecules/summary.py
@@ -40,7 +40,7 @@ class MoleculeSummaryDoc(PropertyDoc):
     Summary information about molecules and their properties, useful for searching.
     """
 
-    property_name = "summary"
+    property_name: str = "summary"
 
     # molecules
     molecules: Dict[str, Molecule] = Field(
@@ -48,26 +48,26 @@ class MoleculeSummaryDoc(PropertyDoc):
         description="The lowest energy optimized structures for this molecule for each solvent.",
     )
 
-    molecule_levels_of_theory: Dict[str, str] = Field(
+    molecule_levels_of_theory: Optional[Dict[str, str]] = Field(
         None,
         description="Level of theory used to optimize the best molecular structure for each solvent.",
     )
 
-    species_hash: str = Field(
+    species_hash: Optional[str] = Field(
         None,
         description="Weisfeiler Lehman (WL) graph hash using the atom species as the graph "
         "node attribute.",
     )
-    coord_hash: str = Field(
+    coord_hash: Optional[str] = Field(
         None,
         description="Weisfeiler Lehman (WL) graph hash using the atom coordinates as the graph "
         "node attribute.",
     )
 
-    inchi: str = Field(
+    inchi: Optional[str] = Field(
         None, description="International Chemical Identifier (InChI) for this molecule"
     )
-    inchi_key: str = Field(
+    inchi_key: Optional[str] = Field(
         None, description="Standardized hash of the InChI for this molecule"
     )
 
@@ -86,244 +86,244 @@ class MoleculeSummaryDoc(PropertyDoc):
         description="IDs of associated MoleculeDocs used to construct this molecule.",
     )
 
-    unique_calc_types: List[CalcType] = Field(
+    unique_calc_types: Optional[List[CalcType]] = Field(
         None,
         description="Collection of all unique calculation types used for this molecule",
     )
 
-    unique_task_types: List[TaskType] = Field(
+    unique_task_types: Optional[List[TaskType]] = Field(
         None,
         description="Collection of all unique task types used for this molecule",
     )
 
-    unique_levels_of_theory: List[LevelOfTheory] = Field(
+    unique_levels_of_theory: Optional[List[LevelOfTheory]] = Field(
         None,
         description="Collection of all unique levels of theory used for this molecule",
     )
 
-    unique_solvents: List[str] = Field(
+    unique_solvents: Optional[List[str]] = Field(
         None,
         description="Collection of all unique solvents (solvent parameters) used for this molecule",
     )
 
-    unique_lot_solvents: List[str] = Field(
+    unique_lot_solvents: Optional[List[str]] = Field(
         None,
         description="Collection of all unique combinations of level of theory and solvent used for this molecule",
     )
 
     # thermo
-    thermo_property_ids: Dict[str, str] = Field(
+    thermo_property_ids: Optional[Dict[str, str]] = Field(
         None,
         description="Solvent:property ID map for each MoleculeThermoDoc for this molecule.",
     )
 
-    thermo_levels_of_theory: Dict[str, str] = Field(
+    thermo_levels_of_theory: Optional[Dict[str, str]] = Field(
         None,
         description="Solvent:level of theory map for each MoleculeThermoDoc for this molecule.",
     )
 
-    electronic_energy: Dict[str, float] = Field(
+    electronic_energy: Optional[Dict[str, float]] = Field(
         None, description="Electronic energy of the molecule (units: eV)"
     )
 
-    zero_point_energy: Dict[str, Optional[float]] = Field(
+    zero_point_energy: Optional[Dict[str, Optional[float]]] = Field(
         None, description="Zero-point energy of the molecule (units: eV)"
     )
 
-    rt: Dict[str, Optional[float]] = Field(
+    rt: Optional[Dict[str, Optional[float]]] = Field(
         None,
         description="R*T, where R is the gas constant and T is temperature, taken "
         "to be 298.15K (units: eV)",
     )
 
-    total_enthalpy: Dict[str, Optional[float]] = Field(
+    total_enthalpy: Optional[Dict[str, Optional[float]]] = Field(
         None, description="Total enthalpy of the molecule at 298.15K (units: eV)"
     )
-    total_entropy: Dict[str, Optional[float]] = Field(
+    total_entropy: Optional[Dict[str, Optional[float]]] = Field(
         None, description="Total entropy of the molecule at 298.15K (units: eV/K)"
     )
 
-    translational_enthalpy: Dict[str, Optional[float]] = Field(
+    translational_enthalpy: Optional[Dict[str, Optional[float]]] = Field(
         None,
         description="Translational enthalpy of the molecule at 298.15K (units: eV)",
     )
-    translational_entropy: Dict[str, Optional[float]] = Field(
+    translational_entropy: Optional[Dict[str, Optional[float]]] = Field(
         None,
         description="Translational entropy of the molecule at 298.15K (units: eV/K)",
     )
-    rotational_enthalpy: Dict[str, Optional[float]] = Field(
+    rotational_enthalpy: Optional[Dict[str, Optional[float]]] = Field(
         None, description="Rotational enthalpy of the molecule at 298.15K (units: eV)"
     )
-    rotational_entropy: Dict[str, Optional[float]] = Field(
+    rotational_entropy: Optional[Dict[str, Optional[float]]] = Field(
         None, description="Rotational entropy of the molecule at 298.15K (units: eV/K)"
     )
-    vibrational_enthalpy: Dict[str, Optional[float]] = Field(
+    vibrational_enthalpy: Optional[Dict[str, Optional[float]]] = Field(
         None, description="Vibrational enthalpy of the molecule at 298.15K (units: eV)"
     )
-    vibrational_entropy: Dict[str, Optional[float]] = Field(
+    vibrational_entropy: Optional[Dict[str, Optional[float]]] = Field(
         None, description="Vibrational entropy of the molecule at 298.15K (units: eV/K)"
     )
 
-    free_energy: Dict[str, Optional[float]] = Field(
+    free_energy: Optional[Dict[str, Optional[float]]] = Field(
         None, description="Gibbs free energy of the molecule at 298.15K (units: eV)"
     )
 
     # vibrational properties
-    vibration_property_ids: Dict[str, str] = Field(
+    vibration_property_ids: Optional[Dict[str, str]] = Field(
         None,
         description="Solvent:property ID map for each VibrationDoc for this molecule.",
     )
 
-    vibration_levels_of_theory: Dict[str, str] = Field(
+    vibration_levels_of_theory: Optional[Dict[str, str]] = Field(
         None,
         description="Solvent:level of theory map for each VibrationDoc for this molecule.",
     )
 
-    frequencies: Dict[str, List[float]] = Field(
+    frequencies: Optional[Dict[str, List[float]]] = Field(
         None, description="List of molecular vibrational frequencies"
     )
 
-    frequency_modes: Dict[str, List[List[List[float]]]] = Field(
+    frequency_modes: Optional[Dict[str, List[List[List[float]]]]] = Field(
         None,
         description="Vibrational frequency modes of the molecule (units: Angstrom)",
     )
 
-    ir_intensities: Dict[str, List[float]] = Field(
+    ir_intensities: Optional[Dict[str, List[float]]] = Field(
         None,
         title="IR intensities",
         description="Intensities for infrared vibrational spectrum peaks",
     )
 
-    ir_activities: Dict[str, List] = Field(
+    ir_activities: Optional[Dict[str, List]] = Field(
         None,
         title="IR activities",
         description="List indicating if frequency-modes are IR-active",
     )
 
     # natural bonding orbitals
-    orbitals_property_ids: Dict[str, str] = Field(
+    orbitals_property_ids: Optional[Dict[str, str]] = Field(
         None,
         description="Solvent:property ID map for each OrbitalDoc for this molecule.",
     )
 
-    orbitals_levels_of_theory: Dict[str, str] = Field(
+    orbitals_levels_of_theory: Optional[Dict[str, str]] = Field(
         None,
         description="Solvent:level of theory map for each OrbitalDoc for this molecule.",
     )
 
-    open_shell: Dict[str, bool] = Field(
+    open_shell: Optional[Dict[str, bool]] = Field(
         None, description="Is this molecule open-shell (spin multiplicity != 1)?"
     )
 
-    nbo_population: Dict[str, Optional[List[NaturalPopulation]]] = Field(
+    nbo_population: Optional[Dict[str, Optional[List[NaturalPopulation]]]] = Field(
         None, description="Natural electron populations of the molecule"
     )
-    nbo_lone_pairs: Dict[str, Optional[List[LonePair]]] = Field(
+    nbo_lone_pairs: Optional[Dict[str, Optional[List[LonePair]]]] = Field(
         None, description="Lone pair orbitals of a closed-shell molecule"
     )
-    nbo_bonds: Dict[str, Optional[List[Bond]]] = Field(
+    nbo_bonds: Optional[Dict[str, Optional[List[Bond]]]] = Field(
         None, description="Bond-like orbitals of a closed-shell molecule"
     )
-    nbo_interactions: Dict[str, Optional[List[Interaction]]] = Field(
+    nbo_interactions: Optional[Dict[str, Optional[List[Interaction]]]] = Field(
         None, description="Orbital-orbital interactions of a closed-shell molecule"
     )
 
-    alpha_population: Dict[str, Optional[List[NaturalPopulation]]] = Field(
+    alpha_population: Optional[Dict[str, Optional[List[NaturalPopulation]]]] = Field(
         None,
         description="Natural electron populations of the alpha electrons of an "
         "open-shell molecule",
     )
-    beta_population: Dict[str, Optional[List[NaturalPopulation]]] = Field(
+    beta_population: Optional[Dict[str, Optional[List[NaturalPopulation]]]] = Field(
         None,
         description="Natural electron populations of the beta electrons of an "
         "open-shell molecule",
     )
-    alpha_lone_pairs: Dict[str, Optional[List[LonePair]]] = Field(
+    alpha_lone_pairs: Optional[Dict[str, Optional[List[LonePair]]]] = Field(
         None, description="Alpha electron lone pair orbitals of an open-shell molecule"
     )
-    beta_lone_pairs: Dict[str, Optional[List[LonePair]]] = Field(
+    beta_lone_pairs: Optional[Dict[str, Optional[List[LonePair]]]] = Field(
         None, description="Beta electron lone pair orbitals of an open-shell molecule"
     )
-    alpha_bonds: Dict[str, Optional[List[Bond]]] = Field(
+    alpha_bonds: Optional[Dict[str, Optional[List[Bond]]]] = Field(
         None, description="Alpha electron bond-like orbitals of an open-shell molecule"
     )
-    beta_bonds: Dict[str, Optional[List[Bond]]] = Field(
+    beta_bonds: Optional[Dict[str, Optional[List[Bond]]]] = Field(
         None, description="Beta electron bond-like orbitals of an open-shell molecule"
     )
-    alpha_interactions: Dict[str, Optional[List[Interaction]]] = Field(
+    alpha_interactions: Optional[Dict[str, Optional[List[Interaction]]]] = Field(
         None,
         description="Alpha electron orbital-orbital interactions of an open-shell molecule",
     )
-    beta_interactions: Dict[str, Optional[List[Interaction]]] = Field(
+    beta_interactions: Optional[Dict[str, Optional[List[Interaction]]]] = Field(
         None,
         description="Beta electron orbital-orbital interactions of an open-shell molecule",
     )
 
     # partial charges
-    partial_charges_property_ids: Dict[str, Dict[str, str]] = Field(
+    partial_charges_property_ids: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Solvent:method:property ID map for each PartialChargesDoc for this molecule.",
     )
 
-    partial_charges_levels_of_theory: Dict[str, Dict[str, str]] = Field(
+    partial_charges_levels_of_theory: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Solvent:method:level of theory map for each PartialChargesDoc for this molecule.",
     )
 
-    partial_charges: Dict[str, Dict[str, List[float]]] = Field(
+    partial_charges: Optional[Dict[str, Dict[str, List[float]]]] = Field(
         None,
         description="Atomic partial charges for the molecule using different partitioning schemes "
         "(Mulliken, Restrained Electrostatic Potential, Natural Bonding Orbitals, etc.)",
     )
 
     # partial spins
-    partial_spins_property_ids: Dict[str, Dict[str, str]] = Field(
+    partial_spins_property_ids: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Solvent:method:property ID map for each PartialSpinsDoc for this molecule.",
     )
 
-    partial_spins_levels_of_theory: Dict[str, Dict[str, str]] = Field(
+    partial_spins_levels_of_theory: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Solvent:method:level of theory map for each PartialSpinsDoc for this molecule.",
     )
 
-    partial_spins: Dict[str, Dict[str, List[float]]] = Field(
+    partial_spins: Optional[Dict[str, Dict[str, List[float]]]] = Field(
         None,
         description="Atomic partial spins for the molecule using different partitioning schemes "
         "(Mulliken, Natural Bonding Orbitals, etc.)",
     )
 
     # bonding
-    bonding_property_ids: Dict[str, Dict[str, str]] = Field(
+    bonding_property_ids: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Solvent:method:property ID map for each MoleculeBondingDoc for this molecule.",
     )
 
-    bonding_levels_of_theory: Dict[str, Dict[str, str]] = Field(
+    bonding_levels_of_theory: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Solvent:method:level of theory map for each MoleculeBondingDoc for this molecule.",
     )
 
-    molecule_graph: Dict[str, Dict[str, MoleculeGraph]] = Field(
+    molecule_graph: Optional[Dict[str, Dict[str, MoleculeGraph]]] = Field(
         None,
         description="Molecular graph representations of the molecule using different "
         "definitions of bonding.",
     )
 
-    bond_types: Dict[str, Dict[str, Dict[str, List[float]]]] = Field(
+    bond_types: Optional[Dict[str, Dict[str, Dict[str, List[float]]]]] = Field(
         None,
         description="Dictionaries of bond types to their length under different "
         "definitions of bonding, e.g. C-O to a list of the lengths of "
         "C-O bonds in Angstrom.",
     )
 
-    bonds: Dict[str, Dict[str, List[Tuple[int, int]]]] = Field(
+    bonds: Optional[Dict[str, Dict[str, List[Tuple[int, int]]]]] = Field(
         None,
         description="List of bonds under different definitions of bonding. Each bond takes "
         "the form (a, b), where a and b are 0-indexed atom indices",
     )
 
-    bonds_nometal: Dict[str, Dict[str, List[Tuple[int, int]]]] = Field(
+    bonds_nometal: Optional[Dict[str, Dict[str, List[Tuple[int, int]]]]] = Field(
         None,
         description="List of bonds under different definitions of bonding with all metal ions "
         "removed. Each bond takes the form in the form (a, b), where a and b are "
@@ -331,125 +331,125 @@ class MoleculeSummaryDoc(PropertyDoc):
     )
 
     # redox properties
-    redox_property_ids: Dict[str, str] = Field(
+    redox_property_ids: Optional[Dict[str, str]] = Field(
         None, description="Solvent:property ID map for each RedoxDoc for this molecule."
     )
 
-    redox_levels_of_theory: Dict[str, str] = Field(
+    redox_levels_of_theory: Optional[Dict[str, str]] = Field(
         None,
         description="Solvent:level of theory map for each RedoxDoc for this molecule.",
     )
 
-    electron_affinity: Dict[str, float] = Field(
+    electron_affinity: Optional[Dict[str, float]] = Field(
         None, description="Vertical electron affinity in eV"
     )
 
-    ea_task_id: Dict[str, MPID] = Field(
+    ea_task_id: Optional[Dict[str, MPID]] = Field(
         None, description="Molecule ID for electron affinity"
     )
 
-    ionization_energy: Dict[str, float] = Field(
+    ionization_energy: Optional[Dict[str, float]] = Field(
         None, description="Vertical ionization energy in eV"
     )
 
-    ie_task_id: Dict[str, MPID] = Field(
+    ie_task_id: Optional[Dict[str, MPID]] = Field(
         None, description="Molecule ID for ionization energy"
     )
 
-    reduction_free_energy: Dict[str, float] = Field(
+    reduction_free_energy: Optional[Dict[str, float]] = Field(
         None, description="Adiabatic free energy of reduction"
     )
 
-    red_molecule_id: Dict[str, MPculeID] = Field(
+    red_molecule_id: Optional[Dict[str, MPculeID]] = Field(
         None, description="Molecule ID for adiabatic reduction"
     )
 
-    oxidation_free_energy: Dict[str, float] = Field(
+    oxidation_free_energy: Optional[Dict[str, float]] = Field(
         None, description="Adiabatic free energy of oxidation"
     )
 
-    ox_molecule_id: Dict[str, MPculeID] = Field(
+    ox_molecule_id: Optional[Dict[str, MPculeID]] = Field(
         None, description="Molecule ID for adiabatic oxidation"
     )
 
-    reduction_potential: Dict[str, float] = Field(
+    reduction_potential: Optional[Dict[str, float]] = Field(
         None,
         description="Reduction potential referenced to the standard hydrogen electrode (SHE) (units: V)",
     )
 
-    oxidation_potential: Dict[str, float] = Field(
+    oxidation_potential: Optional[Dict[str, float]] = Field(
         None,
         description="Oxidation potential referenced to the standard hydrogen electrode (SHE) (units: V)",
     )
 
     # metal binding properties
-    binding_partial_charges_property_id: Dict[str, Dict[str, str]] = Field(
+    binding_partial_charges_property_id: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="ID of PartialChargesDoc used to estimate metal charge",
     )
 
-    binding_partial_spins_property_id: Dict[str, Dict[str, str]] = Field(
+    binding_partial_spins_property_id: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="ID of PartialSpinsDoc used to estimate metal spin",
     )
 
-    binding_partial_charges_lot_solvent: Dict[str, Dict[str, str]] = Field(
+    binding_partial_charges_lot_solvent: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Combination of level of theory and solvent used to calculate atomic partial charges",
     )
 
-    binding_partial_spins_lot_solvent: Dict[str, Dict[str, str]] = Field(
+    binding_partial_spins_lot_solvent: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Combination of level of theory and solvent used to calculate atomic partial spins",
     )
 
-    binding_charge_spin_method: Dict[str, Dict[str, str]] = Field(
+    binding_charge_spin_method: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="The method used for partial charges and spins (must be the same).",
     )
 
-    binding_bonding_property_id: Dict[str, Dict[str, str]] = Field(
+    binding_bonding_property_id: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="ID of MoleculeBondingDoc used to detect bonding in this molecule",
     )
 
-    binding_bonding_lot_solvent: Dict[str, Dict[str, str]] = Field(
+    binding_bonding_lot_solvent: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Combination of level of theory and solvent used to determine the coordination environment "
         "of the metal atom or ion",
     )
 
-    binding_bonding_method: Dict[str, Dict[str, str]] = Field(
+    binding_bonding_method: Optional[Dict[str, Dict[str, str]]] = Field(
         None, description="The method used for to define bonding."
     )
 
-    binding_thermo_property_id: Dict[str, Dict[str, str]] = Field(
+    binding_thermo_property_id: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="ID of MoleculeThermoDoc used to obtain this molecule's thermochemistry",
     )
 
-    binding_thermo_lot_solvent: Dict[str, Dict[str, str]] = Field(
+    binding_thermo_lot_solvent: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Combination of level of theory and solvent used for uncorrected thermochemistry",
     )
 
-    binding_thermo_correction_lot_solvent: Dict[str, Dict[str, str]] = Field(
+    binding_thermo_correction_lot_solvent: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         description="Combination of level of theory and solvent used to correct the electronic energy",
     )
 
-    binding_thermo_combined_lot_solvent: Dict[str, Dict[str, str]] = Field(
+    binding_thermo_combined_lot_solvent: Optional[Dict[str, Dict[str, str]]] = Field(
         None,
         descrption="Combination of level of theory and solvent used for molecular thermochemistry, combining "
         "both the frequency calculation and (potentially) the single-point energy correction.",
     )
 
-    binding_data: Dict[str, Dict[str, List[MetalBindingData]]] = Field(
+    binding_data: Optional[Dict[str, Dict[str, List[MetalBindingData]]]] = Field(
         None, description="Binding data for each metal atom or ion in the molecule"
     )
 
     # has props
-    has_props: List[HasProps] = Field(
+    has_props: Optional[List[HasProps]] = Field(
         None, description="List of properties that are available for a given material."
     )
 
diff --git a/emmet-core/emmet/core/molecules/thermo.py b/emmet-core/emmet/core/molecules/thermo.py
index 640faa7..766a19b 100644
--- a/emmet-core/emmet/core/molecules/thermo.py
+++ b/emmet-core/emmet/core/molecules/thermo.py
@@ -34,7 +34,7 @@ def get_free_energy(energy, enthalpy, entropy, temperature=298.15, convert_energ
 
 
 class MoleculeThermoDoc(PropertyDoc):
-    property_name = "thermo"
+    property_name: str = "thermo"
 
     electronic_energy: float = Field(
         ..., description="Electronic energy of the molecule (units: eV)"
@@ -46,39 +46,39 @@ class MoleculeThermoDoc(PropertyDoc):
         "theory used to correct the electronic energy?",
     )
 
-    base_level_of_theory: LevelOfTheory = Field(
+    base_level_of_theory: Optional[LevelOfTheory] = Field(
         None, description="Level of theory used for uncorrected thermochemistry."
     )
 
-    base_solvent: str = Field(
+    base_solvent: Optional[str] = Field(
         None,
         description="String representation of the solvent "
         "environment used for uncorrected thermochemistry.",
     )
 
-    base_lot_solvent: str = Field(
+    base_lot_solvent: Optional[str] = Field(
         None,
         description="String representation of the level of theory and solvent "
         "environment used for uncorrected thermochemistry.",
     )
 
-    correction_level_of_theory: LevelOfTheory = Field(
+    correction_level_of_theory: Optional[LevelOfTheory] = Field(
         None, description="Level of theory used to correct the electronic energy."
     )
 
-    correction_solvent: str = Field(
+    correction_solvent: Optional[str] = Field(
         None,
         description="String representation of the solvent "
         "environment used to correct the electronic energy.",
     )
 
-    correction_lot_solvent: str = Field(
+    correction_lot_solvent: Optional[str] = Field(
         None,
         description="String representation of the level of theory and solvent "
         "environment used to correct the electronic energy.",
     )
 
-    combined_lot_solvent: str = Field(
+    combined_lot_solvent: Optional[str] = Field(
         None,
         description="String representation of the level of theory and solvent "
         "environment used to generate this ThermoDoc, combining "
@@ -86,45 +86,45 @@ class MoleculeThermoDoc(PropertyDoc):
         "single-point energy correction.",
     )
 
-    zero_point_energy: float = Field(
+    zero_point_energy: Optional[float] = Field(
         None, description="Zero-point energy of the molecule (units: eV)"
     )
 
-    rt: float = Field(
+    rt: Optional[float] = Field(
         None,
         description="R*T, where R is the gas constant and T is temperature, taken "
         "to be 298.15K (units: eV)",
     )
 
-    total_enthalpy: float = Field(
+    total_enthalpy: Optional[float] = Field(
         None, description="Total enthalpy of the molecule at 298.15K (units: eV)"
     )
-    total_entropy: float = Field(
+    total_entropy: Optional[float] = Field(
         None, description="Total entropy of the molecule at 298.15K (units: eV/K)"
     )
 
-    translational_enthalpy: float = Field(
+    translational_enthalpy: Optional[float] = Field(
         None,
         description="Translational enthalpy of the molecule at 298.15K (units: eV)",
     )
-    translational_entropy: float = Field(
+    translational_entropy: Optional[float] = Field(
         None,
         description="Translational entropy of the molecule at 298.15K (units: eV/K)",
     )
-    rotational_enthalpy: float = Field(
+    rotational_enthalpy: Optional[float] = Field(
         None, description="Rotational enthalpy of the molecule at 298.15K (units: eV)"
     )
-    rotational_entropy: float = Field(
+    rotational_entropy: Optional[float] = Field(
         None, description="Rotational entropy of the molecule at 298.15K (units: eV/K)"
     )
-    vibrational_enthalpy: float = Field(
+    vibrational_enthalpy: Optional[float] = Field(
         None, description="Vibrational enthalpy of the molecule at 298.15K (units: eV)"
     )
-    vibrational_entropy: float = Field(
+    vibrational_entropy: Optional[float] = Field(
         None, description="Vibrational entropy of the molecule at 298.15K (units: eV/K)"
     )
 
-    free_energy: float = Field(
+    free_energy: Optional[float] = Field(
         None, description="Gibbs free energy of the molecule at 298.15K (units: eV)"
     )
 
diff --git a/emmet-core/emmet/core/molecules/vibration.py b/emmet-core/emmet/core/molecules/vibration.py
index 0a7c143..73aa30c 100644
--- a/emmet-core/emmet/core/molecules/vibration.py
+++ b/emmet-core/emmet/core/molecules/vibration.py
@@ -15,7 +15,7 @@ __author__ = "Evan Spotte-Smith <ewcspottesmith@lbl.gov>"
 
 
 class VibrationDoc(PropertyDoc):
-    property_name = "vibrations"
+    property_name: str = "vibrations"
 
     molecule: Molecule = Field(..., description="Molecular structure")
 
diff --git a/emmet-core/emmet/core/molecules_jcesr.py b/emmet-core/emmet/core/molecules_jcesr.py
index 10349f5..3d65e27 100644
--- a/emmet-core/emmet/core/molecules_jcesr.py
+++ b/emmet-core/emmet/core/molecules_jcesr.py
@@ -1,4 +1,4 @@
-from typing import List
+from typing import List, Optional
 from pydantic import BaseModel, Field
 from pymatgen.core.periodic_table import Element
 from pymatgen.core.structure import Molecule
@@ -9,58 +9,58 @@ class MoleculesDoc(BaseModel):
     Molecules relevant to battery electrolytes.
     """
 
-    elements: List[Element] = Field(
+    elements: Optional[List[Element]] = Field(
         None,
         description="List of elements in the molecule.",
     )
 
-    nelements: int = Field(
+    nelements: Optional[int] = Field(
         None,
         description="Number of elements in the molecule.",
     )
 
-    EA: float = Field(
+    EA: Optional[float] = Field(
         None,
         description="Electron affinity of the molecule in eV.",
     )
 
-    IE: float = Field(
+    IE: Optional[float] = Field(
         None,
         description="Ionization energy of the molecule in eV.",
     )
 
-    charge: int = Field(
+    charge: Optional[int] = Field(
         None,
         description="Charge of the molecule in +e.",
     )
 
-    pointgroup: str = Field(
+    pointgroup: Optional[str] = Field(
         None,
         description="Point group of the molecule in Schoenflies notation.",
     )
 
-    smiles: str = Field(
+    smiles: Optional[str] = Field(
         None,
         description="The simplified molecular input line-entry system (SMILES) \
             representation of the molecule.",
     )
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="Materials Project molecule ID. This takes the form mol-*****.",
     )
 
-    molecule: Molecule = Field(
+    molecule: Optional[Molecule] = Field(
         None,
         description="Pymatgen molecule object.",
     )
 
-    formula_pretty: str = Field(
+    formula_pretty: Optional[str] = Field(
         None,
         description="Chemical formula of the molecule.",
     )
 
-    svg: str = Field(
+    svg: Optional[str] = Field(
         None,
         description="String representation of the SVG image of the molecule.",
     )
diff --git a/emmet-core/emmet/core/mpcomplete.py b/emmet-core/emmet/core/mpcomplete.py
index ba7100b..9fdc7b1 100644
--- a/emmet-core/emmet/core/mpcomplete.py
+++ b/emmet-core/emmet/core/mpcomplete.py
@@ -2,6 +2,7 @@ from pydantic import Field
 from pydantic.main import BaseModel
 from pymatgen.core.structure import Structure
 from enum import Enum
+from typing import Optional
 
 
 class MPCompleteDoc(BaseModel):
@@ -9,17 +10,17 @@ class MPCompleteDoc(BaseModel):
     Defines data for MPComplete structure submissions
     """
 
-    structure: Structure = Field(
+    structure: Optional[Structure] = Field(
         None,
         description="Structure submitted by the user.",
     )
 
-    public_name: str = Field(
+    public_name: Optional[str] = Field(
         None,
         description="Public name of submitter.",
     )
 
-    public_email: str = Field(
+    public_email: Optional[str] = Field(
         None,
         description="Public email of submitter.",
     )
diff --git a/emmet-core/emmet/core/mpid.py b/emmet-core/emmet/core/mpid.py
index df149cf..079476b 100644
--- a/emmet-core/emmet/core/mpid.py
+++ b/emmet-core/emmet/core/mpid.py
@@ -1,5 +1,10 @@
 import re
-from typing import Union
+from typing import Union, Any, Callable
+
+from pydantic_core import CoreSchema, core_schema
+
+from pydantic import GetJsonSchemaHandler
+from pydantic.json_schema import JsonSchemaValue
 
 
 mpid_regex = re.compile(r"^([A-Za-z]*-)?(\d+)(-[A-Za-z0-9]+)*$")
@@ -80,24 +85,29 @@ class MPID(str):
         return hash(self.string)
 
     @classmethod
-    def __get_validators__(cls):
-        yield cls.validate
+    def __get_pydantic_core_schema__(
+        cls, source: type[Any], handler: Callable[[Any], core_schema.CoreSchema]
+    ) -> core_schema.CoreSchema:
+        return core_schema.with_info_plain_validator_function(cls.validate)
 
     @classmethod
-    def __modify_schema__(cls, field_schema):
-        field_schema.update(
+    def __get_pydantic_json_schema__(
+        cls, core_schema: CoreSchema, handler: GetJsonSchemaHandler
+    ) -> JsonSchemaValue:
+        return dict(
             pattern=r"^([A-Za-z]*-)?(\d+)(-[A-Za-z0-9]+)*$",
             examples=["mp-3534", "3453", "mp-834-Ag"],
+            type="string",
         )
 
     @classmethod
-    def validate(cls, v):
-        if isinstance(v, MPID):
-            return v
-        elif isinstance(v, str) and mpid_regex.fullmatch(v):
-            return MPID(v)
-        elif isinstance(v, int):
-            return MPID(v)
+    def validate(cls, __input_value: Any, _: core_schema.ValidationInfo):
+        if isinstance(__input_value, MPID):
+            return __input_value
+        elif isinstance(__input_value, str) and mpid_regex.fullmatch(__input_value):
+            return MPID(__input_value)
+        elif isinstance(__input_value, int):
+            return MPID(__input_value)
 
         raise ValueError("Invalid MPID Format")
 
@@ -170,25 +180,30 @@ class MPculeID(str):
         return hash(self.string)
 
     @classmethod
-    def __get_validators__(cls):
-        yield cls.validate
+    def __get_pydantic_core_schema__(
+        cls, source: type[Any], handler: Callable[[Any], core_schema.CoreSchema]
+    ) -> core_schema.CoreSchema:
+        return core_schema.with_info_plain_validator_function(cls.validate)
 
     @classmethod
-    def __modify_schema__(cls, field_schema):
-        field_schema.update(
+    def __get_pydantic_json_schema__(
+        cls, core_schema: CoreSchema, handler: GetJsonSchemaHandler
+    ) -> JsonSchemaValue:
+        return dict(
             pattern=r"^^([A-Za-z]+-)?([A-Fa-f0-9]+)-([A-Za-z0-9]+)-(m?[0-9]+)-([0-9]+)$",
             examples=[
                 "1a525231bdac3f13e2fac0962fe8d053-Mg1-0-1",
-                "22b40b99719ac570fc7e6225e855ec6e-F5Li1P1-m1-2"
+                "22b40b99719ac570fc7e6225e855ec6e-F5Li1P1-m1-2",
                 "mpcule-b9ba54febc77d2a9177accf4605767db-C1H41-2",
             ],
+            type="string",
         )
 
     @classmethod
-    def validate(cls, v):
-        if isinstance(v, MPculeID):
-            return v
-        elif isinstance(v, str) and mpculeid_regex.fullmatch(v):
-            return MPculeID(v)
+    def validate(cls, __input_value: Any, _: core_schema.ValidationInfo):
+        if isinstance(__input_value, MPculeID):
+            return __input_value
+        elif isinstance(__input_value, str) and mpculeid_regex.fullmatch(__input_value):
+            return MPculeID(__input_value)
 
         raise ValueError("Invalid MPculeID Format")
diff --git a/emmet-core/emmet/core/oxidation_states.py b/emmet-core/emmet/core/oxidation_states.py
index 45c2a39..107773f 100644
--- a/emmet-core/emmet/core/oxidation_states.py
+++ b/emmet-core/emmet/core/oxidation_states.py
@@ -1,6 +1,6 @@
 import logging
 from collections import defaultdict
-from typing import Dict, List
+from typing import Dict, List, Optional
 
 import numpy as np
 from pydantic import Field
@@ -15,7 +15,7 @@ from emmet.core.mpid import MPID
 class OxidationStateDoc(PropertyDoc):
     """Oxidation states computed from the structure"""
 
-    property_name = "oxidation"
+    property_name: str = "oxidation"
 
     structure: Structure = Field(
         ...,
@@ -30,7 +30,9 @@ class OxidationStateDoc(PropertyDoc):
     average_oxidation_states: Dict[str, float] = Field(
         description="Average oxidation states for each unique species."
     )
-    method: str = Field(None, description="Method used to compute oxidation states.")
+    method: Optional[str] = Field(
+        None, description="Method used to compute oxidation states."
+    )
 
     @classmethod
     def from_structure(cls, structure: Structure, material_id: MPID, **kwargs):  # type: ignore[override]
diff --git a/emmet-core/emmet/core/phonon.py b/emmet-core/emmet/core/phonon.py
index 1a31b4f..c91f1f1 100644
--- a/emmet-core/emmet/core/phonon.py
+++ b/emmet-core/emmet/core/phonon.py
@@ -1,7 +1,7 @@
 from datetime import datetime
 from monty.json import MontyDecoder
 
-from pydantic import BaseModel, Field, validator
+from pydantic import field_validator, BaseModel, Field
 from emmet.core.mpid import MPID
 from pymatgen.phonon.bandstructure import PhononBandStructureSymmLine
 from pymatgen.phonon.dos import PhononDos as PhononDosObject
@@ -20,28 +20,29 @@ class PhononBSDOSDoc(BaseModel):
     Phonon band structures and density of states data.
     """
 
-    material_id: MPID = Field(
+    material_id: Optional[MPID] = Field(
         None,
         description="The Materials Project ID of the material. This comes in the form: mp-******.",
     )
 
-    ph_bs: PhononBandStructureSymmLine = Field(
+    ph_bs: Optional[PhononBandStructureSymmLine] = Field(
         None,
         description="Phonon band structure object.",
     )
 
-    ph_dos: PhononDosObject = Field(
+    ph_dos: Optional[PhononDosObject] = Field(
         None,
         description="Phonon density of states object.",
     )
 
-    last_updated: datetime = Field(
+    last_updated: Optional[datetime] = Field(
         None,
         description="Timestamp for the most recent calculation for this Material document.",
     )
 
     # Make sure that the datetime field is properly formatted
-    @validator("last_updated", pre=True)
+    @field_validator("last_updated", mode="before")
+    @classmethod
     def last_updated_dict_ok(cls, v):
         return MontyDecoder().process_decoded(v)
 
@@ -77,7 +78,7 @@ class PhononBandStructure(BaseModel):
         "bs", description="The type of the document: a phonon band structure."
     )
 
-    band_structure: dict = Field(
+    band_structure: Optional[dict] = Field(
         None,
         description="Serialized version of a pymatgen "
         "PhononBandStructureSymmLine object.",
@@ -109,11 +110,11 @@ class PhononDos(BaseModel):
         "dos", description="The type of the document: a phonon density of states."
     )
 
-    dos: dict = Field(
+    dos: Optional[dict] = Field(
         None, description="Serialized version of a pymatgen CompletePhononDos object."
     )
 
-    dos_method: str = Field(
+    dos_method: Optional[str] = Field(
         None, description="The method used to calculate the phonon DOS."
     )
 
@@ -145,7 +146,7 @@ class PhononWebsiteBS(BaseModel):
         description="The type of the document: a phonon band structure for the phononwebsite.",
     )
 
-    phononwebsite: dict = Field(
+    phononwebsite: Optional[dict] = Field(
         None,
         description="Phononwebsite dictionary to plot the animated " "phonon modes.",
     )
@@ -176,7 +177,7 @@ class Ddb(BaseModel):
         "ddb", description="The type of the document: a DDB file."
     )
 
-    ddb: str = Field(None, description="The string of the DDB file.")
+    ddb: Optional[str] = Field(None, description="The string of the DDB file.")
 
     last_updated: datetime = Field(
         description="Timestamp for the most recent calculation update for this property",
@@ -251,31 +252,33 @@ class Phonon(StructureMetadata):
         ..., description="The relaxed structure for the phonon calculation."
     )
 
-    asr_break: float = Field(
+    asr_break: Optional[float] = Field(
         None, description="The maximum breaking of the acoustic sum rule (ASR)."
     )
 
-    warnings: List[PhononWarnings] = Field(
+    warnings: Optional[List[PhononWarnings]] = Field(
         None, description="List of warnings associated to the phonon calculation."
     )
 
-    dielectric: DielectricDoc = Field(
+    dielectric: Optional[DielectricDoc] = Field(
         None, description="Dielectric properties obtained during a phonon calculations."
     )
 
-    becs: BornEffectiveCharges = Field(
+    becs: Optional[BornEffectiveCharges] = Field(
         None, description="Born effective charges obtained for a phonon calculation."
     )
 
-    ir_spectra: IRDielectric = Field(None, description="The IRDielectricTensor.")
+    ir_spectra: Optional[IRDielectric] = Field(
+        None, description="The IRDielectricTensor."
+    )
 
-    thermodynamic: ThermodynamicProperties = Field(
+    thermodynamic: Optional[ThermodynamicProperties] = Field(
         None,
         description="The thermodynamic properties extracted from the phonon "
         "frequencies.",
     )
 
-    vibrational_energy: VibrationalEnergy = Field(
+    vibrational_energy: Optional[VibrationalEnergy] = Field(
         None, description="The vibrational contributions to the total energy."
     )
 
@@ -296,7 +299,7 @@ class AbinitPhonon(Phonon):
     with Abinit.
     """
 
-    abinit_input_vars: dict = Field(
+    abinit_input_vars: Optional[dict] = Field(
         None,
         description="Dict representation of the inputs used to obtain the phonon"
         "properties and the main general options (e.g. number of "
diff --git a/emmet-core/emmet/core/polar.py b/emmet-core/emmet/core/polar.py
index cdd0b78..fa3263c 100644
--- a/emmet-core/emmet/core/polar.py
+++ b/emmet-core/emmet/core/polar.py
@@ -1,5 +1,5 @@
 """ Core definition for Polar property Document """
-from typing import List
+from typing import List, Optional
 from emmet.core.mpid import MPID
 
 import numpy as np
@@ -24,7 +24,7 @@ class DielectricDoc(PropertyDoc):
     A dielectric property block
     """
 
-    property_name = "dielectric"
+    property_name: str = "dielectric"
 
     total: Matrix3D = Field(description="Total dielectric tensor.")
     ionic: Matrix3D = Field(description="Ionic contribution to dielectric tensor.")
@@ -77,7 +77,7 @@ class PiezoelectricDoc(PropertyDoc):
     A dielectric package block
     """
 
-    property_name = "piezoelectric"
+    property_name: str = "piezoelectric"
 
     total: PiezoTensor = Field(description="Total piezoelectric tensor in C/m²")
     ionic: PiezoTensor = Field(
@@ -143,17 +143,17 @@ class BornEffectiveCharges(BaseModel):
     A block for the Born effective charges
     """
 
-    value: List[Matrix3D] = Field(
+    value: Optional[List[Matrix3D]] = Field(
         None, description="Value of the Born effective charges."
     )
 
-    symmetrized_value: List[Matrix3D] = Field(
+    symmetrized_value: Optional[List[Matrix3D]] = Field(
         None,
         description="Value of the Born effective charges after symmetrization to obey the"
         "charge neutrality sum rule.",
     )
 
-    cnsr_break: float = Field(
+    cnsr_break: Optional[float] = Field(
         None,
         description="The maximum breaking of the charge neutrality sum "
         "rule (CNSR) in the Born effective charges.",
@@ -165,6 +165,6 @@ class IRDielectric(BaseModel):
     A block for the pymatgen IRDielectricTensor object
     """
 
-    ir_dielectric_tensor: dict = Field(
+    ir_dielectric_tensor: Optional[dict] = Field(
         None, description="Serialized version of a pymatgen IRDielectricTensor object."
     )
diff --git a/emmet-core/emmet/core/provenance.py b/emmet-core/emmet/core/provenance.py
index bcd9b37..12c9f70 100644
--- a/emmet-core/emmet/core/provenance.py
+++ b/emmet-core/emmet/core/provenance.py
@@ -5,7 +5,7 @@ from typing import Dict, List, Optional
 
 from pybtex.database import BibliographyData, parse_string
 from pybtex.errors import set_strict_mode
-from pydantic import BaseModel, Field, root_validator, validator
+from pydantic import field_validator, model_validator, BaseModel, Field
 
 from emmet.core.material_property import PropertyDoc
 from emmet.core.mpid import MPID
@@ -28,8 +28,8 @@ class Author(BaseModel):
     Author information
     """
 
-    name: str = Field(None)
-    email: str = Field(None)
+    name: Optional[str] = Field(None)
+    email: Optional[str] = Field(None)
 
 
 class History(BaseModel):
@@ -43,7 +43,8 @@ class History(BaseModel):
         None, description="Dictionary of exra data for this history node."
     )
 
-    @root_validator(pre=True)
+    @model_validator(mode="before")
+    @classmethod
     def str_to_dict(cls, values):
         if isinstance(values.get("description"), str):
             values["description"] = {"string": values.get("description")}
@@ -79,7 +80,8 @@ class SNLAbout(BaseModel):
         default_factory=datetime.utcnow, description="The creation date for this SNL."
     )
 
-    @validator("created_at", pre=True)
+    @field_validator("created_at", mode="before")
+    @classmethod
     def convert_monty_date(cls, v):
         if isinstance(v, dict):
             if v.get("@module", "datetime") and v.get("@class", "datetime"):
@@ -101,7 +103,7 @@ class ProvenanceDoc(PropertyDoc):
     A provenance property block
     """
 
-    property_name = "provenance"
+    property_name: str = "provenance"
 
     created_at: datetime = Field(
         ...,
@@ -134,7 +136,8 @@ class ProvenanceDoc(PropertyDoc):
         " of this material for the entry closest matching the material input",
     )
 
-    @validator("authors")
+    @field_validator("authors")
+    @classmethod
     def remove_duplicate_authors(cls, authors):
         authors_dict = {entry.name.lower(): entry for entry in authors}
         return list(authors_dict.values())
diff --git a/emmet-core/emmet/core/qchem/molecule.py b/emmet-core/emmet/core/qchem/molecule.py
index 909ab88..c93344b 100644
--- a/emmet-core/emmet/core/qchem/molecule.py
+++ b/emmet-core/emmet/core/qchem/molecule.py
@@ -1,5 +1,5 @@
 """ Core definition of a Molecule Document """
-from typing import Any, Dict, List, Mapping, Union
+from typing import Any, Dict, List, Mapping, Union, Optional
 
 from pydantic import Field
 
@@ -140,35 +140,35 @@ def evaluate_task_entry(
 
 
 class MoleculeDoc(CoreMoleculeDoc):
-    species: List[str] = Field(
+    species: Optional[List[str]] = Field(
         None, description="Ordered list of elements/species in this Molecule."
     )
 
-    molecules: Dict[str, Molecule] = Field(
+    molecules: Optional[Dict[str, Molecule]] = Field(
         None,
         description="The lowest energy optimized structures for this molecule for each solvent.",
     )
 
-    molecule_levels_of_theory: Dict[str, str] = Field(
+    molecule_levels_of_theory: Optional[Dict[str, str]] = Field(
         None,
         description="Level of theory used to optimize the best molecular structure for each solvent.",
     )
 
-    species_hash: str = Field(
+    species_hash: Optional[str] = Field(
         None,
         description="Weisfeiler Lehman (WL) graph hash using the atom species as the graph "
         "node attribute.",
     )
-    coord_hash: str = Field(
+    coord_hash: Optional[str] = Field(
         None,
         description="Weisfeiler Lehman (WL) graph hash using the atom coordinates as the graph "
         "node attribute.",
     )
 
-    inchi: str = Field(
+    inchi: Optional[str] = Field(
         None, description="International Chemical Identifier (InChI) for this molecule"
     )
-    inchi_key: str = Field(
+    inchi_key: Optional[str] = Field(
         None, description="Standardized hash of the InChI for this molecule"
     )
 
@@ -176,70 +176,70 @@ class MoleculeDoc(CoreMoleculeDoc):
         None,
         description="Calculation types for all the calculations that make up this molecule",
     )
-    task_types: Mapping[str, TaskType] = Field(
+    task_types: Optional[Mapping[str, TaskType]] = Field(
         None,
         description="Task types for all the calculations that make up this molecule",
     )
-    levels_of_theory: Mapping[str, LevelOfTheory] = Field(
+    levels_of_theory: Optional[Mapping[str, LevelOfTheory]] = Field(
         None,
         description="Levels of theory types for all the calculations that make up this molecule",
     )
-    solvents: Mapping[str, str] = Field(
+    solvents: Optional[Mapping[str, str]] = Field(
         None,
         description="Solvents (solvent parameters) for all the calculations that make up this molecule",
     )
-    lot_solvents: Mapping[str, str] = Field(
+    lot_solvents: Optional[Mapping[str, str]] = Field(
         None,
         description="Combinations of level of theory and solvent for all calculations that make up this molecule",
     )
 
-    unique_calc_types: List[CalcType] = Field(
+    unique_calc_types: Optional[List[CalcType]] = Field(
         None,
         description="Collection of all unique calculation types used for this molecule",
     )
 
-    unique_task_types: List[TaskType] = Field(
+    unique_task_types: Optional[List[TaskType]] = Field(
         None,
         description="Collection of all unique task types used for this molecule",
     )
 
-    unique_levels_of_theory: List[LevelOfTheory] = Field(
+    unique_levels_of_theory: Optional[List[LevelOfTheory]] = Field(
         None,
         description="Collection of all unique levels of theory used for this molecule",
     )
 
-    unique_solvents: List[str] = Field(
+    unique_solvents: Optional[List[str]] = Field(
         None,
         description="Collection of all unique solvents (solvent parameters) used for this molecule",
     )
 
-    unique_lot_solvents: List[str] = Field(
+    unique_lot_solvents: Optional[List[str]] = Field(
         None,
         description="Collection of all unique combinations of level of theory and solvent used for this molecule",
     )
 
-    origins: List[PropertyOrigin] = Field(
+    origins: Optional[List[PropertyOrigin]] = Field(
         None,
         description="List of property origins for tracking the provenance of properties",
     )
 
-    entries: List[Dict[str, Any]] = Field(
+    entries: Optional[List[Dict[str, Any]]] = Field(
         None,
         description="Dictionary representations of all task documents for this molecule",
     )
 
-    best_entries: Mapping[str, Dict[str, Any]] = Field(
+    best_entries: Optional[Mapping[str, Dict[str, Any]]] = Field(
         None,
         description="Mapping for tracking the best entries at each level of theory (+ solvent) for Q-Chem calculations",
     )
 
-    constituent_molecules: List[MPculeID] = Field(
+    constituent_molecules: Optional[List[MPculeID]] = Field(
         None,
         description="For cases where data from multiple MoleculeDocs have been compiled, a list of "
         "MPculeIDs of documents used to construct this document",
     )
 
-    similar_molecules: List[MPculeID] = Field(
+    similar_molecules: Optional[List[MPculeID]] = Field(
         None,
         description="List of MPculeIDs with of molecules similar (by e.g. structure) to this one",
     )
@@ -532,7 +532,7 @@ def best_lot(
     """
 
     sorted_lots = sorted(
-        mol_doc.best_entries.keys(),
+        mol_doc.best_entries.keys(),  # type: ignore
         key=lambda x: evaluate_lot(x, funct_scores, basis_scores, solvent_scores),
     )
 
diff --git a/emmet-core/emmet/core/qchem/task.py b/emmet-core/emmet/core/qchem/task.py
index 6b4b5eb..4a1fa2a 100644
--- a/emmet-core/emmet/core/qchem/task.py
+++ b/emmet-core/emmet/core/qchem/task.py
@@ -38,31 +38,35 @@ class OutputSummary(BaseModel):
     Summary of an output for a Q-Chem calculation
     """
 
-    initial_molecule: Molecule = Field(None, description="Input Molecule object")
-    optimized_molecule: Molecule = Field(None, description="Optimized Molecule object")
+    initial_molecule: Optional[Molecule] = Field(
+        None, description="Input Molecule object"
+    )
+    optimized_molecule: Optional[Molecule] = Field(
+        None, description="Optimized Molecule object"
+    )
 
-    final_energy: float = Field(
+    final_energy: Optional[float] = Field(
         None, description="Final electronic energy for the calculation (units: Hartree)"
     )
-    enthalpy: float = Field(
+    enthalpy: Optional[float] = Field(
         None, description="Total enthalpy of the molecule (units: kcal/mol)"
     )
-    entropy: float = Field(
+    entropy: Optional[float] = Field(
         None, description="Total entropy of the molecule (units: cal/mol-K"
     )
 
-    mulliken: List[Any] = Field(
+    mulliken: Optional[List[Any]] = Field(
         None, description="Mulliken atomic partial charges and partial spins"
     )
-    resp: List[float] = Field(
+    resp: Optional[List[float]] = Field(
         None,
         description="Restrained Electrostatic Potential (RESP) atomic partial charges",
     )
-    nbo: Dict[str, Any] = Field(
+    nbo: Optional[Dict[str, Any]] = Field(
         None, description="Natural Bonding Orbital (NBO) output"
     )
 
-    frequencies: List[float] = Field(
+    frequencies: Optional[List[float]] = Field(
         None, description="Vibrational frequencies of the molecule (units: cm^-1)"
     )
 
@@ -87,16 +91,18 @@ class TaskDocument(BaseTaskDocument, MoleculeMetadata):
     Definition of a Q-Chem task document
     """
 
-    calc_code = "Q-Chem"
-    completed = True
+    calc_code: str = "Q-Chem"
+    completed: bool = True
 
     is_valid: bool = Field(
         True, description="Whether this task document passed validation or not"
     )
-    state: QChemStatus = Field(None, description="State of this calculation")
+    state: Optional[QChemStatus] = Field(None, description="State of this calculation")
 
-    cputime: float = Field(None, description="The system CPU time in seconds")
-    walltime: float = Field(None, description="The real elapsed time in seconds")
+    cputime: Optional[float] = Field(None, description="The system CPU time in seconds")
+    walltime: Optional[float] = Field(
+        None, description="The real elapsed time in seconds"
+    )
 
     calcs_reversed: List[Dict] = Field(
         [], description="The 'raw' calculation docs used to assembled this task"
@@ -105,31 +111,31 @@ class TaskDocument(BaseTaskDocument, MoleculeMetadata):
     orig: Dict[str, Any] = Field(
         {}, description="Summary of the original Q-Chem inputs"
     )
-    output = Field(OutputSummary())
+    output: OutputSummary = Field(OutputSummary())
 
-    critic2: Dict[str, Any] = Field(
+    critic2: Optional[Dict[str, Any]] = Field(
         None, description="Output from Critic2 critical point analysis code"
     )
-    custom_smd: str = Field(
+    custom_smd: Optional[str] = Field(
         None, description="Parameter string for SMD implicit solvent model"
     )
 
-    special_run_type: str = Field(
+    special_run_type: Optional[str] = Field(
         None, description="Special workflow name (if applicable)"
     )
 
-    smiles: str = Field(
+    smiles: Optional[str] = Field(
         None,
         description="Simplified molecular-input line-entry system (SMILES) string for the molecule involved "
         "in this calculation.",
     )
 
-    species_hash: str = Field(
+    species_hash: Optional[str] = Field(
         None,
         description="Weisfeiler Lehman (WL) graph hash using the atom species as the graph "
         "node attribute.",
     )
-    coord_hash: str = Field(
+    coord_hash: Optional[str] = Field(
         None,
         description="Weisfeiler Lehman (WL) graph hash using the atom coordinates as the graph "
         "node attribute.",
@@ -138,9 +144,9 @@ class TaskDocument(BaseTaskDocument, MoleculeMetadata):
     # TODO - type of `tags` field seems to differ among task databases
     # sometimes List, sometimes Dict
     # left as Any here to ensure tags don't cause validation to fail.
-    tags: Any = Field(None, description="Metadata tags")
+    tags: Optional[Any] = Field(None, description="Metadata tags")
 
-    warnings: Dict[str, bool] = Field(
+    warnings: Optional[Dict[str, bool]] = Field(
         None, description="Any warnings related to this task document"
     )
 
diff --git a/emmet-core/emmet/core/robocrys.py b/emmet-core/emmet/core/robocrys.py
index b781552..fd82121 100644
--- a/emmet-core/emmet/core/robocrys.py
+++ b/emmet-core/emmet/core/robocrys.py
@@ -1,4 +1,4 @@
-from typing import Union
+from typing import Union, Optional
 
 from pydantic import BaseModel, Field
 from pymatgen.core.structure import Structure
@@ -16,7 +16,7 @@ class MineralData(BaseModel):
         description="Mineral type.",
     )
 
-    name: str = Field(None, description="The mineral name if found.")
+    name: Optional[str] = Field(None, description="The mineral name if found.")
 
 
 class CondensedStructureData(BaseModel):
@@ -33,17 +33,17 @@ class CondensedStructureData(BaseModel):
         description="Dimensionality of the material.",
     )
 
-    formula: str = Field(
+    formula: Optional[str] = Field(
         None,
         description="Formula for the material.",
     )
 
-    spg_symbol: str = Field(
+    spg_symbol: Optional[str] = Field(
         None,
         description="Space group symbol of the material.",
     )
 
-    crystal_system: str = Field(
+    crystal_system: Optional[str] = Field(
         None,
         description="Crystal system of the material.",
     )
@@ -57,7 +57,7 @@ class RobocrystallogapherDoc(PropertyDoc):
 
     """
 
-    property_name = "robocrys"
+    property_name: str = "robocrys"
 
     description: str = Field(
         description="Decription text from robocrytallographer.",
diff --git a/emmet-core/emmet/core/settings.py b/emmet-core/emmet/core/settings.py
index c441660..eeb6300 100644
--- a/emmet-core/emmet/core/settings.py
+++ b/emmet-core/emmet/core/settings.py
@@ -9,9 +9,11 @@ from typing import Dict, List, Type, TypeVar, Union
 
 import requests
 from monty.json import MontyDecoder
-from pydantic import BaseSettings, Field, root_validator
-from pydantic.class_validators import validator
-from pydantic.types import PyObject
+from pydantic import field_validator, model_validator, Field, ImportString
+from pydantic_settings import BaseSettings, SettingsConfigDict
+
+# pydantic 1 name, kept for code that subclasses EmmetSettings and still imports it from here.
+PyObject = ImportString
 
 DEFAULT_CONFIG_FILE_PATH = str(Path.home().joinpath(".emmet.json"))
 
@@ -121,7 +123,7 @@ class EmmetSettings(BaseSettings):
         description="Relative tolerance for kspacing to still be a valid task document",
     )
 
-    VASP_DEFAULT_INPUT_SETS: Dict[str, PyObject] = Field(
+    VASP_DEFAULT_INPUT_SETS: Dict[str, ImportString] = Field(
         {
             "GGA Structure Optimization": "pymatgen.io.vasp.sets.MPRelaxSet",
             "GGA+U Structure Optimization": "pymatgen.io.vasp.sets.MPRelaxSet",
@@ -167,12 +169,10 @@ class EmmetSettings(BaseSettings):
         True,
         description="Use static calculations for structure and energy along with structure optimizations",
     )
+    model_config = SettingsConfigDict(env_prefix="emmet_", extra="ignore")
 
-    class Config:
-        env_prefix = "emmet_"
-        extra = "ignore"
-
-    @root_validator(pre=True)
+    @model_validator(mode="before")
+    @classmethod
     def load_default_settings(cls, values):
         """
         Loads settings from a root file if available and uses that as defaults in
@@ -200,7 +200,8 @@ class EmmetSettings(BaseSettings):
             return cls(**settings)
         return settings
 
-    @validator("VASP_DEFAULT_INPUT_SETS", pre=True)
+    @field_validator("VASP_DEFAULT_INPUT_SETS", mode="before")
+    @classmethod
     def convert_input_sets(cls, value):
         if isinstance(value, dict):
             return {k: MontyDecoder().process_decoded(v) for k, v in value.items()}
diff --git a/emmet-core/emmet/core/similarity.py b/emmet-core/emmet/core/similarity.py
index 935027b..fe517d8 100644
--- a/emmet-core/emmet/core/similarity.py
+++ b/emmet-core/emmet/core/similarity.py
@@ -1,4 +1,4 @@
-from typing import List
+from typing import List, Optional
 
 from pydantic import BaseModel, Field
 
@@ -8,22 +8,22 @@ class SimilarityEntry(BaseModel):
     Find similar materials to a specified material based on crystal geometry.
     """
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The Materials Project ID for the matched material. This comes in the form: mp-******.",
     )
 
-    nelements: int = Field(
+    nelements: Optional[int] = Field(
         None,
         description="Number of elements in the matched material.",
     )
 
-    dissimilarity: float = Field(
+    dissimilarity: Optional[float] = Field(
         None,
         description="Dissimilarity measure for the matched material in %.",
     )
 
-    formula: str = Field(
+    formula: Optional[str] = Field(
         None,
         description="Formula of the matched material.",
     )
@@ -34,12 +34,12 @@ class SimilarityDoc(BaseModel):
     Model for a document containing structure similarity data
     """
 
-    sim: List[SimilarityEntry] = Field(
+    sim: Optional[List[SimilarityEntry]] = Field(
         None,
         description="List containing similar structure data for a given material.",
     )
 
-    material_id: str = Field(
+    material_id: Optional[str] = Field(
         None,
         description="The Materials Project ID for the material. This comes in the form: mp-******",
     )
diff --git a/emmet-core/emmet/core/structure.py b/emmet-core/emmet/core/structure.py
index 5a60b86..14b0763 100644
--- a/emmet-core/emmet/core/structure.py
+++ b/emmet-core/emmet/core/structure.py
@@ -22,51 +22,55 @@ class StructureMetadata(EmmetBaseModel):
     """
 
     # Structure metadata
-    nsites: int = Field(None, description="Total number of sites in the structure.")
-    elements: List[Element] = Field(
+    nsites: Optional[int] = Field(
+        None, description="Total number of sites in the structure."
+    )
+    elements: Optional[List[Element]] = Field(
         None, description="List of elements in the material."
     )
-    nelements: int = Field(None, description="Number of elements.")
-    composition: Composition = Field(
+    nelements: Optional[int] = Field(None, description="Number of elements.")
+    composition: Optional[Composition] = Field(
         None, description="Full composition for the material."
     )
-    composition_reduced: Composition = Field(
+    composition_reduced: Optional[Composition] = Field(
         None,
         title="Reduced Composition",
         description="Simplified representation of the composition.",
     )
-    formula_pretty: str = Field(
+    formula_pretty: Optional[str] = Field(
         None,
         title="Pretty Formula",
         description="Cleaned representation of the formula.",
     )
-    formula_anonymous: str = Field(
+    formula_anonymous: Optional[str] = Field(
         None,
         title="Anonymous Formula",
         description="Anonymized representation of the formula.",
     )
-    chemsys: str = Field(
+    chemsys: Optional[str] = Field(
         None,
         title="Chemical System",
         description="dash-delimited string of elements in the material.",
     )
-    volume: float = Field(
+    volume: Optional[float] = Field(
         None,
         title="Volume",
         description="Total volume for this structure in Angstroms^3.",
     )
 
-    density: float = Field(
+    density: Optional[float] = Field(
         None, title="Density", description="Density in grams per cm^3."
     )
 
-    density_atomic: float = Field(
+    density_atomic: Optional[float] = Field(
         None,
         title="Packing Density",
         description="The atomic packing density in atoms per cm^3.",
     )
 
-    symmetry: SymmetryData = Field(None, description="Symmetry data for this material.")
+    symmetry: Optional[SymmetryData] = Field(
+        None, description="Symmetry data for this material."
+    )
 
     @classmethod
     def from_composition(
@@ -156,49 +160,51 @@ class MoleculeMetadata(EmmetBaseModel):
     Mix-in class for molecule metadata
     """
 
-    charge: int = Field(None, description="Charge of the molecule")
-    spin_multiplicity: int = Field(
+    charge: Optional[int] = Field(None, description="Charge of the molecule")
+    spin_multiplicity: Optional[int] = Field(
         None, description="Spin multiplicity of the molecule"
     )
-    natoms: int = Field(None, description="Total number of atoms in the molecule")
-    elements: List[Element] = Field(
+    natoms: Optional[int] = Field(
+        None, description="Total number of atoms in the molecule"
+    )
+    elements: Optional[List[Element]] = Field(
         None, description="List of elements in the molecule"
     )
-    nelements: int = Field(None, title="Number of Elements")
-    nelectrons: int = Field(
+    nelements: Optional[int] = Field(None, title="Number of Elements")
+    nelectrons: Optional[int] = Field(
         None,
         title="Number of electrons",
         description="The total number of electrons for the molecule",
     )
-    composition: Composition = Field(
+    composition: Optional[Composition] = Field(
         None, description="Full composition for the molecule"
     )
-    composition_reduced: Composition = Field(
+    composition_reduced: Optional[Composition] = Field(
         None,
         title="Reduced Composition",
         description="Simplified representation of the composition",
     )
-    formula_alphabetical: str = Field(
+    formula_alphabetical: Optional[str] = Field(
         None,
         title="Alphabetical Formula",
         description="Alphabetical molecular formula",
     )
-    formula_pretty: str = Field(
+    formula_pretty: Optional[str] = Field(
         None,
         title="Pretty Formula",
         description="Cleaned representation of the formula.",
     )
-    formula_anonymous: str = Field(
+    formula_anonymous: Optional[str] = Field(
         None,
         title="Anonymous Formula",
         description="Anonymized representation of the formula",
     )
-    chemsys: str = Field(
+    chemsys: Optional[str] = Field(
         None,
         title="Chemical System",
         description="dash-delimited string of elements in the molecule",
     )
-    symmetry: PointGroupData = Field(
+    symmetry: Optional[PointGroupData] = Field(
         None, description="Symmetry data for this molecule"
     )
 
diff --git a/emmet-core/emmet/core/structure_group.py b/emmet-core/emmet/core/structure_group.py
index 9c598e6..1a8bae2 100644
--- a/emmet-core/emmet/core/structure_group.py
+++ b/emmet-core/emmet/core/structure_group.py
@@ -5,7 +5,7 @@ from itertools import groupby
 from typing import Iterable, List, Optional, Union
 
 from monty.json import MontyDecoder
-from pydantic import BaseModel, Field, validator
+from pydantic import field_validator, BaseModel, Field
 from pymatgen.analysis.structure_matcher import ElementComparator, StructureMatcher
 from pymatgen.core.composition import Composition
 from pymatgen.entries.computed_entries import ComputedEntry, ComputedStructureEntry
@@ -49,54 +49,55 @@ class StructureGroupDoc(BaseModel):
     Group of structure
     """
 
-    group_id: str = Field(
+    group_id: Optional[str] = Field(
         None,
         description="The combined material_id of the grouped document is given by the numerically smallest "
         "material_id, you can also append the followed by the ignored species at the end.",
     )
 
-    has_distinct_compositions: bool = Field(
+    has_distinct_compositions: Optional[bool] = Field(
         None, description="True if multiple compositions are present in the group."
     )
 
-    material_ids: list = Field(
+    material_ids: Optional[list] = Field(
         None,
         description="A list of materials ids for all of the materials that were grouped together.",
     )
 
-    host_material_ids: list = Field(
+    host_material_ids: Optional[list] = Field(
         None,
         description="Material id(s) that correspond(s) to the host structure(s), which has/have the lowest"
         "concentration of ignored specie.",
     )
 
-    insertion_material_ids: list = Field(
+    insertion_material_ids: Optional[list] = Field(
         None,
         description="Material ids that correspond to the non-host structures identified in a given structure group.",
     )
 
-    framework_formula: str = Field(
+    framework_formula: Optional[str] = Field(
         None,
         description="The chemical formula for the framework (the materials system without the ignored species).",
     )
 
-    ignored_specie: str = Field(
+    ignored_specie: Optional[str] = Field(
         None,
         description="Ignored atomic specie which is usually the working ion (ex: Li, Mg, or Ca).",
     )
 
-    chemsys: str = Field(
+    chemsys: Optional[str] = Field(
         None,
         description="The chemical system this group belongs to, if the atoms for the ignored species is "
         "present the chemsys will also include the ignored species.",
     )
 
-    last_updated: datetime = Field(
+    last_updated: Optional[datetime] = Field(
         None, description="Timestamp when this document was built."
     )
 
     # Make sure that the datetime field is properly formatted
-    @validator("last_updated", pre=True)
+    @field_validator("last_updated", mode="before")
+    @classmethod
     def last_updated_dict_ok(cls, v):
         return MontyDecoder().process_decoded(v)
 
@@ -192,7 +193,7 @@ class StructureGroupDoc(BaseModel):
                 struct_group = cls.from_grouped_entries(
                     f_group_l, ignored_specie=ignored_specie
                 )
-                cnt_ += len(struct_group.material_ids)
+                cnt_ += len(struct_group.material_ids)  # type: ignore
                 continue
 
             logger.debug(
@@ -202,7 +203,7 @@ class StructureGroupDoc(BaseModel):
                 struct_group = cls.from_grouped_entries(
                     g, ignored_specie=ignored_specie
                 )
-                cnt_ += len(struct_group.material_ids)
+                cnt_ += len(struct_group.material_ids)  # type: ignore
                 results.append(struct_group)
         if cnt_ != len(entries):
             raise RuntimeError(
diff --git a/emmet-core/emmet/core/substrates.py b/emmet-core/emmet/core/substrates.py
index 25e18d7..1f9aa3b 100644
--- a/emmet-core/emmet/core/substrates.py
+++ b/emmet-core/emmet/core/substrates.py
@@ -1,4 +1,5 @@
 from pydantic import BaseModel, Field
+from typing import Optional
 
 
 class SubstratesDoc(BaseModel):
@@ -6,42 +7,43 @@ class SubstratesDoc(BaseModel):
     Possible growth substrates for a given material.
     """
 
-    sub_form: str = Field(
+    sub_form: Optional[str] = Field(
         None,
         description="Reduced formula of the substrate.",
     )
 
-    sub_id: str = Field(
+    sub_id: Optional[str] = Field(
         None,
         description="Materials Project ID of the substrate material. This comes in the form: mp-******.",
     )
 
-    film_orient: str = Field(
+    film_orient: Optional[str] = Field(
         None,
         description="Surface orientation of the film material.",
     )
 
-    area: float = Field(
+    area: Optional[float] = Field(
         None,
         description="Minimum coincident interface area in Å².",
     )
 
-    energy: float = Field(
+    energy: Optional[float] = Field(
         None,
         description="Elastic energy in meV.",
     )
 
-    film_id: str = Field(
+    film_id: Optional[str] = Field(
         None,
         description="The Materials Project ID of the film material. This comes in the form: mp-******.",
     )
 
-    _norients: int = Field(
+    norients: Optional[int] = Field(
         None,
         description="Number of possible surface orientations for the substrate.",
+        alias="_norients",
     )
 
-    orient: str = Field(
+    orient: Optional[str] = Field(
         None,
         description="Surface orientation of the substrate material.",
     )
diff --git a/emmet-core/emmet/core/summary.py b/emmet-core/emmet/core/summary.py
index 9eaef77..841d63b 100644
--- a/emmet-core/emmet/core/summary.py
+++ b/emmet-core/emmet/core/summary.py
@@ -47,7 +47,7 @@ class SummaryStats(BaseModel):
     Statistics about a specified SummaryDoc field.
     """
 
-    field: str = Field(
+    field: Optional[str] = Field(
         None,
         title="Field",
         description="Field name corresponding to a field in SummaryDoc.",
@@ -58,25 +58,27 @@ class SummaryStats(BaseModel):
         description="The number of documents sampled to generate statistics. "
         "If unspecified, statistics will be from entire database.",
     )
-    min: float = Field(
+    min: Optional[float] = Field(
         None,
         title="Minimum",
         description="The minimum value "
         "of the specified field used to "
         "generate statistics.",
     )
-    max: float = Field(
+    max: Optional[float] = Field(
         None,
         title="Maximum",
         description="The maximum value "
         "of the specified field used to "
         "generate statistics.",
     )
-    median: float = Field(
+    median: Optional[float] = Field(
         None, title="Median", description="The median of the field values."
     )
-    mean: float = Field(None, title="Mean", description="The mean of the field values.")
-    distribution: List[float] = Field(
+    mean: Optional[float] = Field(
+        None, title="Mean", description="The mean of the field values."
+    )
+    distribution: Optional[List[float]] = Field(
         None,
         title="Distribution",
         description="List of floats specifying a kernel density "
@@ -90,17 +92,19 @@ class XASSearchData(BaseModel):
     Fields in XAS sub docs in summary
     """
 
-    edge: Edge = Field(
+    edge: Optional[Edge] = Field(
         None,
         title="Absorption Edge",
         description="The interaction edge for XAS",
         source="xas",
     )
-    absorbing_element: Element = Field(
+    absorbing_element: Optional[Element] = Field(
         None, description="Absorbing element.", source="xas"
     )
 
-    spectrum_type: Type = Field(None, description="Type of XAS spectrum.", source="xas")
+    spectrum_type: Optional[Type] = Field(
+        None, description="Type of XAS spectrum.", source="xas"
+    )
 
 
 class GBSearchData(BaseModel):
@@ -108,17 +112,19 @@ class GBSearchData(BaseModel):
     Fields in grain boundary sub docs in summary
     """
 
-    sigma: int = Field(
+    sigma: Optional[int] = Field(
         None, description="Sigma value of the boundary.", source="grain_boundary"
     )
 
-    type: str = Field(None, description="Grain boundary type.", source="grain_boundary")
+    type: Optional[str] = Field(
+        None, description="Grain boundary type.", source="grain_boundary"
+    )
 
-    gb_energy: float = Field(
+    gb_energy: Optional[float] = Field(
         None, description="Grain boundary energy in J/m^2.", source="grain_boundary"
     )
 
-    rotation_angle: float = Field(
+    rotation_angle: Optional[float] = Field(
         None, description="Rotation angle in degrees.", source="grain_boundary"
     )
 
@@ -129,7 +135,7 @@ class SummaryDoc(PropertyDoc):
     screening studies and searching.
     """
 
-    property_name = "summary"
+    property_name: str = "summary"
 
     # Materials
 
@@ -148,25 +154,25 @@ class SummaryDoc(PropertyDoc):
 
     # Thermo
 
-    uncorrected_energy_per_atom: float = Field(
+    uncorrected_energy_per_atom: Optional[float] = Field(
         None,
         description="The total DFT energy of this material per atom in eV/atom.",
         source="thermo",
     )
 
-    energy_per_atom: float = Field(
+    energy_per_atom: Optional[float] = Field(
         None,
         description="The total corrected DFT energy of this material per atom in eV/atom.",
         source="thermo",
     )
 
-    formation_energy_per_atom: float = Field(
+    formation_energy_per_atom: Optional[float] = Field(
         None,
         description="The formation energy per atom in eV/atom.",
         source="thermo",
     )
 
-    energy_above_hull: float = Field(
+    energy_above_hull: Optional[float] = Field(
         None,
         description="The energy above the hull in eV/Atom.",
         source="thermo",
@@ -178,14 +184,14 @@ class SummaryDoc(PropertyDoc):
         source="thermo",
     )
 
-    equilibrium_reaction_energy_per_atom: float = Field(
+    equilibrium_reaction_energy_per_atom: Optional[float] = Field(
         None,
         description="The reaction energy of a stable entry from the neighboring equilibrium stable materials in eV."
         " Also known as the inverse distance to hull.",
         source="thermo",
     )
 
-    decomposes_to: List[DecompositionProduct] = Field(
+    decomposes_to: Optional[List[DecompositionProduct]] = Field(
         None,
         description="List of decomposition data for this material. Only valid for metastable or unstable material.",
         source="thermo",
@@ -193,13 +199,13 @@ class SummaryDoc(PropertyDoc):
 
     # XAS
 
-    xas: List[XASSearchData] = Field(
+    xas: Optional[List[XASSearchData]] = Field(
         None, description="List of xas documents.", source="xas"
     )
 
     # GB
 
-    grain_boundaries: List[GBSearchData] = Field(
+    grain_boundaries: Optional[List[GBSearchData]] = Field(
         None,
         description="List of grain boundary documents.",
         source="grain_boundary",
@@ -207,47 +213,47 @@ class SummaryDoc(PropertyDoc):
 
     # Electronic Structure
 
-    band_gap: float = Field(
+    band_gap: Optional[float] = Field(
         None, description="Band gap energy in eV.", source="electronic_structure"
     )
 
-    cbm: Union[float, Dict] = Field(
+    cbm: Optional[Union[float, Dict]] = Field(
         None, description="Conduction band minimum data.", source="electronic_structure"
     )
 
-    vbm: Union[float, Dict] = Field(
+    vbm: Optional[Union[float, Dict]] = Field(
         None, description="Valence band maximum data.", source="electronic_structure"
     )
 
-    efermi: float = Field(
+    efermi: Optional[float] = Field(
         None, description="Fermi energy in eV.", source="electronic_structure"
     )
 
-    is_gap_direct: bool = Field(
+    is_gap_direct: Optional[bool] = Field(
         None,
         description="Whether the band gap is direct.",
         source="electronic_structure",
     )
 
-    is_metal: bool = Field(
+    is_metal: Optional[bool] = Field(
         None,
         description="Whether the material is a metal.",
         source="electronic_structure",
     )
 
-    es_source_calc_id: Union[MPID, int] = Field(
+    es_source_calc_id: Optional[Union[MPID, int]] = Field(
         None,
         description="The source calculation ID for the electronic structure data.",
         source="electronic_structure",
     )
 
-    bandstructure: BandstructureData = Field(
+    bandstructure: Optional[BandstructureData] = Field(
         None,
         description="Band structure data for the material.",
         source="electronic_structure",
     )
 
-    dos: DosData = Field(
+    dos: Optional[DosData] = Field(
         None,
         description="Density of states data for the material.",
         source="electronic_structure",
@@ -255,131 +261,137 @@ class SummaryDoc(PropertyDoc):
 
     # DOS
 
-    dos_energy_up: float = Field(
+    dos_energy_up: Optional[float] = Field(
         None, description="Spin-up DOS band gap in eV.", source="electronic_structure"
     )
 
-    dos_energy_down: float = Field(
+    dos_energy_down: Optional[float] = Field(
         None, description="Spin-down DOS band gap in eV.", source="electronic_structure"
     )
 
     # Magnetism
 
-    is_magnetic: bool = Field(
+    is_magnetic: Optional[bool] = Field(
         None, description="Whether the material is magnetic.", source="magnetism"
     )
 
-    ordering: str = Field(
+    ordering: Optional[str] = Field(
         None, description="Type of magnetic ordering.", source="magnetism"
     )
 
-    total_magnetization: float = Field(
+    total_magnetization: Optional[float] = Field(
         None, description="Total magnetization in μB.", source="magnetism"
     )
 
-    total_magnetization_normalized_vol: float = Field(
+    total_magnetization_normalized_vol: Optional[float] = Field(
         None,
         description="Total magnetization normalized by volume in μB/Å³.",
         source="magnetism",
     )
 
-    total_magnetization_normalized_formula_units: float = Field(
+    total_magnetization_normalized_formula_units: Optional[float] = Field(
         None,
         description="Total magnetization normalized by formula unit in μB/f.u. .",
         source="magnetism",
     )
 
-    num_magnetic_sites: int = Field(
+    num_magnetic_sites: Optional[int] = Field(
         None, description="The number of magnetic sites.", source="magnetism"
     )
 
-    num_unique_magnetic_sites: int = Field(
+    num_unique_magnetic_sites: Optional[int] = Field(
         None, description="The number of unique magnetic sites.", source="magnetism"
     )
 
-    types_of_magnetic_species: List[Element] = Field(
+    types_of_magnetic_species: Optional[List[Element]] = Field(
         None, description="Magnetic specie elements.", source="magnetism"
     )
 
     # Elasticity
 
-    k_voigt: float = Field(None, description="Voigt average of the bulk modulus.")
+    k_voigt: Optional[float] = Field(
+        None, description="Voigt average of the bulk modulus."
+    )
 
-    k_reuss: float = Field(
+    k_reuss: Optional[float] = Field(
         None, description="Reuss average of the bulk modulus in GPa."
     )
 
-    k_vrh: float = Field(
+    k_vrh: Optional[float] = Field(
         None, description="Voigt-Reuss-Hill average of the bulk modulus in GPa."
     )
 
-    g_voigt: float = Field(
+    g_voigt: Optional[float] = Field(
         None, description="Voigt average of the shear modulus in GPa."
     )
 
-    g_reuss: float = Field(
+    g_reuss: Optional[float] = Field(
         None, description="Reuss average of the shear modulus in GPa."
     )
 
-    g_vrh: float = Field(
+    g_vrh: Optional[float] = Field(
         None, description="Voigt-Reuss-Hill average of the shear modulus in GPa."
     )
 
-    universal_anisotropy: float = Field(None, description="Elastic anisotropy.")
+    universal_anisotropy: Optional[float] = Field(
+        None, description="Elastic anisotropy."
+    )
 
-    homogeneous_poisson: float = Field(None, description="Poisson's ratio.")
+    homogeneous_poisson: Optional[float] = Field(None, description="Poisson's ratio.")
 
     # Dielectric and Piezo
 
-    e_total: float = Field(
+    e_total: Optional[float] = Field(
         None, description="Total dielectric constant.", source="dielectric"
     )
 
-    e_ionic: float = Field(
+    e_ionic: Optional[float] = Field(
         None,
         description="Ionic contribution to dielectric constant.",
         source="dielectric",
     )
 
-    e_electronic: float = Field(
+    e_electronic: Optional[float] = Field(
         None,
         description="Electronic contribution to dielectric constant.",
         source="dielectric",
     )
 
-    n: float = Field(None, description="Refractive index.", source="dielectric")
+    n: Optional[float] = Field(
+        None, description="Refractive index.", source="dielectric"
+    )
 
-    e_ij_max: float = Field(
+    e_ij_max: Optional[float] = Field(
         None, description="Piezoelectric modulus.", source="piezoelectric"
     )
 
     # Surface Properties
 
-    weighted_surface_energy_EV_PER_ANG2: float = Field(
+    weighted_surface_energy_EV_PER_ANG2: Optional[float] = Field(
         None,
         description="Weighted surface energy in eV/Å².",
         source="surface_properties",
     )
 
-    weighted_surface_energy: float = Field(
+    weighted_surface_energy: Optional[float] = Field(
         None,
         description="Weighted surface energy in J/m².",
         source="surface_properties",
     )
 
-    weighted_work_function: float = Field(
+    weighted_work_function: Optional[float] = Field(
         None, description="Weighted work function in eV.", source="surface_properties"
     )
 
-    surface_anisotropy: float = Field(
+    surface_anisotropy: Optional[float] = Field(
         None, description="Surface energy anisotropy.", source="surface_properties"
     )
 
-    shape_factor: float = Field(
+    shape_factor: Optional[float] = Field(
         None, description="Shape factor.", source="surface_properties"
     )
 
-    has_reconstructed: bool = Field(
+    has_reconstructed: Optional[bool] = Field(
         None,
         description="Whether the material has any reconstructed surfaces.",
         source="surface_properties",
@@ -387,7 +399,7 @@ class SummaryDoc(PropertyDoc):
 
     # Oxi States
 
-    possible_species: List[str] = Field(
+    possible_species: Optional[List[str]] = Field(
         None,
         description="Possible charged species in this material.",
         source="oxidation_states",
@@ -395,7 +407,7 @@ class SummaryDoc(PropertyDoc):
 
     # Has Props
 
-    has_props: List[HasProps] = Field(
+    has_props: Optional[List[HasProps]] = Field(
         None,
         description="List of properties that are available for a given material.",
         source="summary",
diff --git a/emmet-core/emmet/core/surface_properties.py b/emmet-core/emmet/core/surface_properties.py
index b46a01f..fcee35d 100644
--- a/emmet-core/emmet/core/surface_properties.py
+++ b/emmet-core/emmet/core/surface_properties.py
@@ -1,4 +1,4 @@
-from typing import List
+from typing import List, Optional
 from pymatgen.core.structure import Structure
 
 from pydantic import BaseModel, Field
@@ -9,47 +9,47 @@ class SurfaceEntry(BaseModel):
     Surface energies, miller indicies, ...
     """
 
-    miller_index: List[int] = Field(
+    miller_index: Optional[List[int]] = Field(
         None,
         description="Miller index of surface.",
     )
 
-    surface_energy_EV_PER_ANG2: float = Field(
+    surface_energy_EV_PER_ANG2: Optional[float] = Field(
         None,
         description="Surface energy in eV/Å².",
     )
 
-    surface_energy: float = Field(
+    surface_energy: Optional[float] = Field(
         None,
         description="Surface energy in J/m².",
     )
 
-    is_reconstructed: bool = Field(
+    is_reconstructed: Optional[bool] = Field(
         None,
         description="Whether it is a reconstructed surface.",
     )
 
-    structure: str = Field(
+    structure: Optional[str] = Field(
         None,
         description="CIF of slab structure.",
     )
 
-    work_function: float = Field(
+    work_function: Optional[float] = Field(
         None,
         description="Work function in eV.",
     )
 
-    efermi: float = Field(
+    efermi: Optional[float] = Field(
         None,
         description="Fermi energy in eV.",
     )
 
-    area_fraction: float = Field(
+    area_fraction: Optional[float] = Field(
         None,
         description="Area fraction.",
     )
 
-    has_wulff: bool = Field(
+    has_wulff: Optional[bool] = Field(
         None,
         description="Whether the surface has wulff entry.",
     )
@@ -60,52 +60,52 @@ class SurfacePropDoc(BaseModel):
     Model for a document containing surface properties data
     """
 
-    surfaces: List[SurfaceEntry] = Field(
+    surfaces: Optional[List[SurfaceEntry]] = Field(
         None,
         description="List of individual surface data.",
     )
 
-    weighted_surface_energy_EV_PER_ANG2: float = Field(
+    weighted_surface_energy_EV_PER_ANG2: Optional[float] = Field(
         None,
         description="Weighted surface energy in eV/Å²",
     )
 
-    weighted_surface_energy: float = Field(
+    weighted_surface_energy: Optional[float] = Field(
         None,
         description="Weighted surface energy in J/m²",
     )
 
-    surface_anisotropy: float = Field(
+    surface_anisotropy: Optional[float] = Field(
         None,
         description="Surface energy anisotropy.",
     )
 
-    pretty_formula: str = Field(
+    pretty_formula: Optional[str] = Field(
         None,
         description="Reduced Formula of the material.",
     )
 
-    shape_factor: float = Field(
+    shape_factor: Optional[float] = Field(
         None,
         description="Shape factor.",
     )
 
-    weighted_work_function: float = Field(
+    weighted_work_function: Optional[float] = Field(
         None,
         description="Weighted work function in eV.",
     )
 
-    has_reconstructed: bool = Field(
+    has_reconstructed: Optional[bool] = Field(
         None,
         description="Whether the entry has any reconstructed surfaces.",
     )
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The Materials Project ID of the material. This comes in the form: mp-******.",
     )
 
-    structure: Structure = Field(
+    structure: Optional[Structure] = Field(
         None,
         description="The conventional crystal structure of the material.",
     )
diff --git a/emmet-core/emmet/core/symmetry.py b/emmet-core/emmet/core/symmetry.py
index 5282c5c..4c27155 100644
--- a/emmet-core/emmet/core/symmetry.py
+++ b/emmet-core/emmet/core/symmetry.py
@@ -1,4 +1,4 @@
-from typing import Any, Dict
+from typing import Any, Dict, Optional
 
 from pydantic import BaseModel, Field
 from pymatgen.core import Structure
@@ -30,33 +30,33 @@ class PointGroupData(BaseModel):
     Defines symmetry for a molecule document
     """
 
-    point_group: str = Field(
+    point_group: Optional[str] = Field(
         None, title="Point Group Symbol", description="The point group for the lattice"
     )
 
-    rotation_number: float = Field(
+    rotation_number: Optional[float] = Field(
         None,
         title="Rotational Symmetry Number",
         description="Rotational symmetry number for the molecule",
     )
 
-    linear: bool = Field(
+    linear: Optional[bool] = Field(
         None, title="Molecule Linearity", description="Is the molecule linear?"
     )
 
-    tolerance: float = Field(
+    tolerance: Optional[float] = Field(
         None,
         title="Point Group Analyzer Tolerance",
         description="Distance tolerance to consider sites as symmetrically equivalent.",
     )
 
-    eigen_tolerance: float = Field(
+    eigen_tolerance: Optional[float] = Field(
         None,
         title="Interia Tensor Eigenvalue Tolerance",
         description="Tolerance to compare eigen values of the inertia tensor.",
     )
 
-    matrix_tolerance: float = Field(
+    matrix_tolerance: Optional[float] = Field(
         None,
         title="Symmetry Operation Matrix Element Tolerance",
         description="Tolerance used to generate the full set of symmetry operations of the point group.",
@@ -116,33 +116,33 @@ class SymmetryData(BaseModel):
     Defines a symmetry data set for materials documents
     """
 
-    crystal_system: CrystalSystem = Field(
+    crystal_system: Optional[CrystalSystem] = Field(
         None, title="Crystal System", description="The crystal system for this lattice."
     )
 
-    symbol: str = Field(
+    symbol: Optional[str] = Field(
         None,
         title="Space Group Symbol",
         description="The spacegroup symbol for the lattice.",
     )
 
-    number: int = Field(
+    number: Optional[int] = Field(
         None,
         title="Space Group Number",
         description="The spacegroup number for the lattice.",
     )
 
-    point_group: str = Field(
+    point_group: Optional[str] = Field(
         None, title="Point Group Symbol", description="The point group for the lattice."
     )
 
-    symprec: float = Field(
+    symprec: Optional[float] = Field(
         None,
         title="Symmetry Finding Precision",
         description="The precision given to spglib to determine the symmetry of this lattice.",
     )
 
-    version: str = Field(None, title="SPGLib version")
+    version: Optional[str] = Field(None, title="SPGLib version")
 
     @classmethod
     def from_structure(cls, structure: Structure) -> "SymmetryData":
diff --git a/emmet-core/emmet/core/synthesis/materials.py b/emmet-core/emmet/core/synthesis/materials.py
index 7b3b8be..e279376 100644
--- a/emmet-core/emmet/core/synthesis/materials.py
+++ b/emmet-core/emmet/core/synthesis/materials.py
@@ -14,7 +14,7 @@ class Component(BaseModel):
 
 
 class Values(BaseModel):
-    values: List[float] = Field(None, description="List of values.")
+    values: Optional[List[float]] = Field(None, description="List of values.")
     min_value: Optional[float] = Field(None, description="Minimal value.")
     max_value: Optional[float] = Field(None, description="Maximal value.")
 
@@ -30,12 +30,14 @@ class ExtractedMaterial(BaseModel):
     material_formula: str = Field(
         ..., description="Normalized formula of the material."
     )
-    material_name: str = Field(None, description="English name of the material.")
+    material_name: Optional[str] = Field(
+        None, description="English name of the material."
+    )
 
     phase: Optional[str] = Field(
         None, description="Phase description of material, such as anatase."
     )
-    is_acronym: bool = Field(
+    is_acronym: Optional[bool] = Field(
         None, description="Whether the material is an acronym, such as LMO for LiMn2O4."
     )
 
diff --git a/emmet-core/emmet/core/synthesis/operations.py b/emmet-core/emmet/core/synthesis/operations.py
index d9e6b89..20325fa 100644
--- a/emmet-core/emmet/core/synthesis/operations.py
+++ b/emmet-core/emmet/core/synthesis/operations.py
@@ -5,8 +5,8 @@ from pydantic import BaseModel, Field
 
 
 class Value(BaseModel):
-    min_value: float = Field(None, description="Minimal value.")
-    max_value: float = Field(None, description="Maximal value.")
+    min_value: Optional[float] = Field(None, description="Minimal value.")
+    max_value: Optional[float] = Field(None, description="Maximal value.")
     values: List[float] = Field([], description="Enumerated values in the literature.")
     units: str = Field(..., description="Unit of this value.")
 
diff --git a/emmet-core/emmet/core/task.py b/emmet-core/emmet/core/task.py
index 71c9443..55b646b 100644
--- a/emmet-core/emmet/core/task.py
+++ b/emmet-core/emmet/core/task.py
@@ -1,6 +1,6 @@
 """ Core definition of a Task Document which represents a calculation from some program"""
 from datetime import datetime
-from typing import Union
+from typing import Union, Optional
 
 from pydantic import Field
 
@@ -14,14 +14,16 @@ class BaseTaskDocument(EmmetBaseModel):
     """
 
     calc_code: str = Field(description="The calculation code used to compute this task")
-    version: str = Field(None, description="The version of the calculation code")
-    dir_name: str = Field(None, description="The directory for this task")
-    task_id: Union[MPID, MPculeID] = Field(
+    version: Optional[str] = Field(
+        None, description="The version of the calculation code"
+    )
+    dir_name: Optional[str] = Field(None, description="The directory for this task")
+    task_id: Optional[Union[MPID, MPculeID]] = Field(
         None, description="the Task ID For this document"
     )
 
     completed: bool = Field(False, description="Whether this calcuation completed")
-    completed_at: datetime = Field(
+    completed_at: Optional[datetime] = Field(
         None, description="Timestamp for when this task was completed"
     )
     last_updated: datetime = Field(
diff --git a/emmet-core/emmet/core/tasks.py b/emmet-core/emmet/core/tasks.py
index 3944f30..2861820 100644
--- a/emmet-core/emmet/core/tasks.py
+++ b/emmet-core/emmet/core/tasks.py
@@ -10,7 +10,7 @@ from typing import Any, Dict, List, Optional, Tuple, Type, TypeVar, Union
 import numpy as np
 from monty.json import MontyDecoder
 from monty.serialization import loadfn
-from pydantic import BaseModel, Field, validator
+from pydantic import field_validator, ConfigDict, BaseModel, Field, model_validator
 from pymatgen.analysis.structure_analyzer import oxide_type
 from pymatgen.core.structure import Structure
 from pymatgen.core.trajectory import Trajectory
@@ -36,70 +36,76 @@ _VOLUMETRIC_FILES = ("CHGCAR", "LOCPOT", "AECCAR0", "AECCAR1", "AECCAR2")
 
 
 class Potcar(BaseModel):
-    pot_type: str = Field(None, description="Pseudo-potential type, e.g. PAW")
-    functional: str = Field(None, description="Functional type use in the calculation.")
-    symbols: List[str] = Field(
+    pot_type: Optional[str] = Field(None, description="Pseudo-potential type, e.g. PAW")
+    functional: Optional[str] = Field(
+        None, description="Functional type use in the calculation."
+    )
+    symbols: Optional[List[str]] = Field(
         None, description="List of VASP potcar symbols used in the calculation."
     )
 
 
 class OrigInputs(BaseModel):
-    incar: Union[Incar, Dict] = Field(
+    incar: Optional[Union[Incar, Dict]] = Field(
         None,
         description="Pymatgen object representing the INCAR file.",
     )
 
-    poscar: Poscar = Field(
+    poscar: Optional[Poscar] = Field(
         None,
         description="Pymatgen object representing the POSCAR file.",
     )
 
-    kpoints: Kpoints = Field(
+    kpoints: Optional[Kpoints] = Field(
         None,
         description="Pymatgen object representing the KPOINTS file.",
     )
 
-    potcar: Union[Potcar, VaspPotcar, List[Any]] = Field(
+    potcar: Optional[Union[Potcar, VaspPotcar, List[Any]]] = Field(
         None,
         description="Pymatgen object representing the POTCAR file.",
     )
 
-    @validator("potcar", pre=True)
+    @field_validator("potcar", mode="before")
+    @classmethod
     def potcar_ok(cls, v):
         if isinstance(v, list):
             return [i for i in v]
         return v
 
-    class Config:
-        arbitrary_types_allowed = True
+    model_config = ConfigDict(arbitrary_types_allowed=True)
 
 
 class OutputDoc(BaseModel):
-    structure: Structure = Field(
+    structure: Optional[Structure] = Field(
         None,
         title="Output Structure",
         description="Output Structure from the VASP calculation.",
     )
 
-    density: float = Field(None, description="Density of in units of g/cc.")
+    density: Optional[float] = Field(None, description="Density of in units of g/cc.")
     energy: float = Field(..., description="Total Energy in units of eV.")
-    forces: List[List[float]] = Field(
+    forces: Optional[List[List[float]]] = Field(
         None, description="The force on each atom in units of eV/A^2."
     )
-    stress: List[List[float]] = Field(
+    stress: Optional[List[List[float]]] = Field(
         None, description="The stress on the cell in units of kB."
     )
-    energy_per_atom: float = Field(
+    energy_per_atom: Optional[float] = Field(
         None, description="The final DFT energy per atom for the last calculation"
     )
-    bandgap: float = Field(None, description="The DFT bandgap for the last calculation")
+    bandgap: Optional[float] = Field(
+        None, description="The DFT bandgap for the last calculation"
+    )
 
-    @validator("density", pre=True, always=True)
-    def set_density_from_structure(cls, v, values, **kwargs):
+    @model_validator(mode="before")
+    def set_density_from_structure(cls, values):
         # Validator to automatically set density from structure if not already
         # specified. This might happen when importing an older atomate2-format
         # TaskDocument.
-        return v or values["structure"].density
+        if not values.get("density", None):
+            values["density"] = values["structure"].density
+        return values
 
     @classmethod
     def from_vasp_calc_doc(
@@ -145,30 +151,30 @@ class OutputDoc(BaseModel):
 
 
 class InputDoc(BaseModel):
-    structure: Structure = Field(
+    structure: Optional[Structure] = Field(
         None,
         title="Input Structure",
         description="Output Structure from the VASP calculation.",
     )
 
-    parameters: Dict = Field(
+    parameters: Optional[Dict] = Field(
         None,
         description="Parameters from vasprun for the last calculation in the series",
     )
-    pseudo_potentials: Potcar = Field(
+    pseudo_potentials: Optional[Potcar] = Field(
         None, description="Summary of the pseudo-potentials used in this calculation"
     )
-    potcar_spec: List[PotcarSpec] = Field(
+    potcar_spec: Optional[List[PotcarSpec]] = Field(
         None, description="Title and hash of POTCAR files used in the calculation"
     )
-    xc_override: str = Field(
+    xc_override: Optional[str] = Field(
         None, description="Exchange-correlation functional used if not the default"
     )
-    is_lasph: bool = Field(
+    is_lasph: Optional[bool] = Field(
         None, description="Whether the calculation was run with aspherical corrections"
     )
     is_hubbard: bool = Field(False, description="Is this a Hubbard +U calculation")
-    hubbards: Dict = Field(None, description="The hubbard parameters used")
+    hubbards: Optional[dict] = Field(None, description="The hubbard parameters used")
 
     @classmethod
     def from_vasp_calc_doc(cls, calc_doc: Calculation) -> "InputDoc":
@@ -205,12 +211,12 @@ class InputDoc(BaseModel):
 
 
 class CustodianDoc(BaseModel):
-    corrections: List[Any] = Field(
+    corrections: Optional[List[Any]] = Field(
         None,
         title="Custodian Corrections",
         description="List of custodian correction data for calculation.",
     )
-    job: dict = Field(
+    job: Optional[dict] = Field(
         None,
         title="Cusotodian Job Data",
         description="Job data logged by custodian.",
@@ -218,29 +224,29 @@ class CustodianDoc(BaseModel):
 
 
 class AnalysisDoc(BaseModel):
-    delta_volume: float = Field(
+    delta_volume: Optional[float] = Field(
         None,
         title="Volume Change",
         description="Volume change for the calculation.",
     )
-    delta_volume_percent: float = Field(
+    delta_volume_percent: Optional[float] = Field(
         None,
         title="Volume Change Percent",
         description="Percent volume change for the calculation.",
     )
-    max_force: float = Field(
+    max_force: Optional[float] = Field(
         None,
         title="Max Force",
         description="Maximum force on any atom at the end of the calculation.",
     )
 
-    warnings: List[str] = Field(
+    warnings: Optional[List[str]] = Field(
         None,
         title="Calculation Warnings",
         description="Warnings issued after analysis.",
     )
 
-    errors: List[str] = Field(
+    errors: Optional[List[str]] = Field(
         None,
         title="Calculation Errors",
         description="Errors issued after analysis.",
@@ -299,7 +305,7 @@ class AnalysisDoc(BaseModel):
         )
 
 
-class TaskDoc(StructureMetadata):
+class TaskDoc(StructureMetadata, extra="allow"):
     """
     Calculation-level details about VASP calculations that power Materials Project.
     """
@@ -307,95 +313,102 @@ class TaskDoc(StructureMetadata):
     tags: Union[List[str], None] = Field(
         [], title="tag", description="Metadata tagged to a given task."
     )
-    dir_name: str = Field(None, description="The directory for this VASP task")
+    dir_name: Optional[str] = Field(
+        None, description="The directory for this VASP task"
+    )
 
-    state: TaskState = Field(None, description="State of this calculation")
+    state: Optional[TaskState] = Field(None, description="State of this calculation")
 
-    calcs_reversed: List[Calculation] = Field(
+    calcs_reversed: Optional[List[Calculation]] = Field(
         None,
         title="Calcs reversed data",
         description="Detailed data for each VASP calculation contributing to the task document.",
     )
 
-    structure: Structure = Field(
+    structure: Optional[Structure] = Field(
         None, description="Final output structure from the task"
     )
 
-    task_type: Union[CalcType, TaskType] = Field(
+    task_type: Optional[Union[CalcType, TaskType]] = Field(
         None, description="The type of calculation."
     )
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The (task) ID of this calculation, used as a universal reference across property documents."
         "This comes in the form: mp-******.",
     )
 
-    orig_inputs: OrigInputs = Field(
+    orig_inputs: Optional[OrigInputs] = Field(
         None,
         description="The exact set of input parameters used to generate the current task document.",
     )
 
-    input: InputDoc = Field(
+    input: Optional[InputDoc] = Field(
         None,
         description="The input structure used to generate the current task document.",
     )
 
-    output: OutputDoc = Field(
+    output: Optional[OutputDoc] = Field(
         None,
         description="The exact set of output parameters used to generate the current task document.",
     )
 
-    included_objects: List[VaspObject] = Field(
+    included_objects: Optional[List[VaspObject]] = Field(
         None, description="List of VASP objects included with this task document"
     )
-    vasp_objects: Dict[VaspObject, Any] = Field(
+    vasp_objects: Optional[Dict[VaspObject, Any]] = Field(
         None, description="Vasp objects associated with this task"
     )
-    entry: ComputedEntry = Field(
+    entry: Optional[ComputedEntry] = Field(
         None, description="The ComputedEntry from the task doc"
     )
 
-    task_label: str = Field(None, description="A description of the task")
-    author: str = Field(None, description="Author extracted from transformations")
-    icsd_id: str = Field(
+    task_label: Optional[str] = Field(None, description="A description of the task")
+    author: Optional[str] = Field(
+        None, description="Author extracted from transformations"
+    )
+    icsd_id: Optional[Union[str, int]] = Field(
         None, description="Inorganic Crystal Structure Database id of the structure"
     )
-    transformations: Dict[str, Any] = Field(
+    transformations: Optional[Dict[str, Any]] = Field(
         None,
         description="Information on the structural transformations, parsed from a "
         "transformations.json file",
     )
-    additional_json: Dict[str, Any] = Field(
+    additional_json: Optional[Dict[str, Any]] = Field(
         None, description="Additional json loaded from the calculation directory"
     )
 
-    custodian: List[CustodianDoc] = Field(
+    custodian: Optional[List[CustodianDoc]] = Field(
         None,
         title="Calcs reversed data",
         description="Detailed custodian data for each VASP calculation contributing to the task document.",
     )
 
-    analysis: AnalysisDoc = Field(
+    analysis: Optional[AnalysisDoc] = Field(
         None,
         title="Calculation Analysis",
         description="Some analysis of calculation data after collection.",
     )
 
-    last_updated: datetime = Field(
+    last_updated: Optional[datetime] = Field(
         None,
         description="Timestamp for the most recent calculation for this task document",
     )
 
     # Make sure that the datetime field is properly formatted
     # (Unclear when this is not the case, please leave comment if observed)
-    @validator("last_updated", pre=True)
+    @field_validator("last_updated", mode="before")
+    @classmethod
     def last_updated_dict_ok(cls, v) -> datetime:
         return v if isinstance(v, datetime) else monty_decoder.process_decoded(v)
 
-    @validator("entry", pre=True)
-    def set_entry(cls, v, values) -> datetime:
-        return v or cls.get_entry(values["calcs_reversed"], values["task_id"])
+    @model_validator(mode="after")
+    def set_entry(self) -> datetime:
+        if not self.entry and (self.calcs_reversed and self.task_id):
+            self.entry = self.get_entry(self.calcs_reversed, self.task_id)
+        return self
 
     @classmethod
     def from_directory(
@@ -501,7 +514,7 @@ class TaskDoc(StructureMetadata):
             included_objects=included_objects,
             task_type=calcs_reversed[0].task_type,
         )
-        doc = doc.copy(update=additional_fields)
+        doc = doc.model_copy(update=additional_fields)
         return doc
 
     @classmethod
@@ -645,13 +658,13 @@ class TrajectoryDoc(BaseModel):
     Model for task trajectory data
     """
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The (task) ID of this calculation, used as a universal reference across property documents."
         "This comes in the form: mp-******.",
     )
 
-    trajectories: List[Trajectory] = Field(
+    trajectories: Optional[List[Trajectory]] = Field(
         None,
         description="Trajectory data for calculations associated with a task doc.",
     )
@@ -662,13 +675,13 @@ class EntryDoc(BaseModel):
     Model for task entry data
     """
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The (task) ID of this calculation, used as a universal reference across property documents."
         "This comes in the form: mp-******.",
     )
 
-    entry: ComputedStructureEntry = Field(
+    entry: Optional[ComputedStructureEntry] = Field(
         None,
         description="Computed structure entry for the calculation associated with the task doc.",
     )
@@ -679,18 +692,18 @@ class DeprecationDoc(BaseModel):
     Model for task deprecation data
     """
 
-    task_id: str = Field(
+    task_id: Optional[str] = Field(
         None,
         description="The (task) ID of this calculation, used as a universal reference across property documents."
         "This comes in the form: mp-******.",
     )
 
-    deprecated: bool = Field(
+    deprecated: Optional[bool] = Field(
         None,
         description="Whether the ID corresponds to a deprecated calculation.",
     )
 
-    deprecation_reason: str = Field(
+    deprecation_reason: Optional[str] = Field(
         None,
         description="Reason for deprecation.",
     )
diff --git a/emmet-core/emmet/core/thermo.py b/emmet-core/emmet/core/thermo.py
index 7939d03..b7c4643 100644
--- a/emmet-core/emmet/core/thermo.py
+++ b/emmet-core/emmet/core/thermo.py
@@ -19,15 +19,15 @@ class DecompositionProduct(BaseModel):
     Entry metadata for a decomposition process
     """
 
-    material_id: MPID = Field(
+    material_id: Optional[MPID] = Field(
         None,
         description="The Materials Project ID for the material this decomposition points to.",
     )
-    formula: str = Field(
+    formula: Optional[str] = Field(
         None,
         description="The formula of the decomposed material this material decomposes to.",
     )
-    amount: float = Field(
+    amount: Optional[float] = Field(
         None,
         description="The amount of the decomposed material by formula units this this material decomposes to.",
     )
@@ -45,7 +45,7 @@ class ThermoDoc(PropertyDoc):
     A thermo entry document
     """
 
-    property_name = "thermo"
+    property_name: str = "thermo"
 
     thermo_type: Union[ThermoType, RunType] = Field(
         ...,
@@ -66,9 +66,9 @@ class ThermoDoc(PropertyDoc):
         description="The total corrected DFT energy of this material per atom in eV/atom.",
     )
 
-    energy_uncertainy_per_atom: float = Field(None, description="")
+    energy_uncertainy_per_atom: Optional[float] = Field(None, description="")
 
-    formation_energy_per_atom: float = Field(
+    formation_energy_per_atom: Optional[float] = Field(
         None, description="The formation energy per atom in eV/atom."
     )
 
@@ -81,23 +81,23 @@ class ThermoDoc(PropertyDoc):
         description="Flag for whether this material is on the hull and therefore stable.",
     )
 
-    equilibrium_reaction_energy_per_atom: float = Field(
+    equilibrium_reaction_energy_per_atom: Optional[float] = Field(
         None,
         description="The reaction energy of a stable entry from the neighboring equilibrium stable materials in eV."
         " Also known as the inverse distance to hull.",
     )
 
-    decomposes_to: List[DecompositionProduct] = Field(
+    decomposes_to: Optional[List[DecompositionProduct]] = Field(
         None,
         description="List of decomposition data for this material. Only valid for metastable or unstable material.",
     )
 
-    decomposition_enthalpy: float = Field(
+    decomposition_enthalpy: Optional[float] = Field(
         None,
         description="Decomposition enthalpy as defined by `get_decomp_and_phase_separation_energy` in pymatgen.",
     )
 
-    decomposition_enthalpy_decomposes_to: List[DecompositionProduct] = Field(
+    decomposition_enthalpy_decomposes_to: Optional[List[DecompositionProduct]] = Field(
         None,
         description="List of decomposition data associated with the decomposition_enthalpy quantity.",
     )
@@ -293,7 +293,7 @@ class PhaseDiagramDoc(BaseModel):
     A phase diagram document
     """
 
-    property_name = "phase_diagram"
+    property_name: str = "phase_diagram"
 
     phase_diagram_id: str = Field(
         ...,
diff --git a/emmet-core/emmet/core/utils.py b/emmet-core/emmet/core/utils.py
index 0c62ec1..53762d4 100644
--- a/emmet-core/emmet/core/utils.py
+++ b/emmet-core/emmet/core/utils.py
@@ -268,7 +268,7 @@ def jsanitize(obj, strict=False, allow_bson=False):
     if isinstance(obj, BaseModel):
         return {
             k.__str__(): jsanitize(v, strict=strict, allow_bson=allow_bson)
-            for k, v in obj.dict().items()
+            for k, v in obj.model_dump().items()
         }
     if isinstance(obj, (int, float)):
         if np.isnan(obj):
diff --git a/emmet-core/emmet/core/vasp/calculation.py b/emmet-core/emmet/core/vasp/calculation.py
index 342da48..af7699c 100644
--- a/emmet-core/emmet/core/vasp/calculation.py
+++ b/emmet-core/emmet/core/vasp/calculation.py
@@ -5,10 +5,10 @@
 import logging
 from pathlib import Path
 from typing import Any, Dict, List, Optional, Tuple, Union
+from datetime import datetime
 
 import numpy as np
 from pydantic import BaseModel, Extra, Field
-from pydantic.datetime_parse import datetime
 from pymatgen.command_line.bader_caller import bader_analysis_from_path
 from pymatgen.core.lattice import Lattice
 from pymatgen.core.structure import Structure
@@ -63,8 +63,8 @@ class VaspObject(ValueEnum):
 class PotcarSpec(BaseModel):
     """Document defining a VASP POTCAR specification."""
 
-    titel: str = Field(None, description="TITEL field from POTCAR header")
-    hash: str = Field(None, description="md5 hash of POTCAR file")
+    titel: Optional[str] = Field(None, description="TITEL field from POTCAR header")
+    hash: Optional[str] = Field(None, description="md5 hash of POTCAR file")
 
     @classmethod
     def from_potcar_single(cls, potcar_single: PotcarSingle) -> "PotcarSpec":
@@ -105,27 +105,31 @@ class PotcarSpec(BaseModel):
 class CalculationInput(BaseModel):
     """Document defining VASP calculation inputs."""
 
-    incar: Dict[str, Any] = Field(
+    incar: Optional[Dict[str, Any]] = Field(
         None, description="INCAR parameters for the calculation"
     )
-    kpoints: Union[Dict[str, Any], Kpoints] = Field(
+    kpoints: Optional[Union[Dict[str, Any], Kpoints]] = Field(
         None, description="KPOINTS for the calculation"
     )
-    nkpoints: int = Field(None, description="Total number of k-points")
-    potcar: List[str] = Field(None, description="POTCAR symbols in the calculation")
-    potcar_spec: List[PotcarSpec] = Field(
+    nkpoints: Optional[int] = Field(None, description="Total number of k-points")
+    potcar: Optional[List[str]] = Field(
+        None, description="POTCAR symbols in the calculation"
+    )
+    potcar_spec: Optional[List[PotcarSpec]] = Field(
         None, description="Title and hash of POTCAR files used in the calculation"
     )
-    potcar_type: List[str] = Field(None, description="List of POTCAR functional types.")
-    parameters: Dict = Field(None, description="Parameters from vasprun")
-    lattice_rec: Lattice = Field(
+    potcar_type: Optional[List[str]] = Field(
+        None, description="List of POTCAR functional types."
+    )
+    parameters: Optional[dict] = Field(None, description="Parameters from vasprun")
+    lattice_rec: Optional[Lattice] = Field(
         None, description="Reciprocal lattice of the structure"
     )
-    structure: Structure = Field(
+    structure: Optional[Structure] = Field(
         None, description="Input structure for the calculation"
     )
     is_hubbard: bool = Field(False, description="Is this a Hubbard +U calculation")
-    hubbards: Dict = Field(None, description="The hubbard parameters used")
+    hubbards: Optional[dict] = Field(None, description="The hubbard parameters used")
 
     @classmethod
     def from_vasprun(cls, vasprun: Vasprun) -> "CalculationInput":
@@ -147,6 +151,7 @@ class CalculationInput(BaseModel):
             {"abc": list(k), "weight": w}
             for k, w in zip(vasprun.actual_kpoints, vasprun.actual_kpoints_weights)
         ]
+
         return cls(
             structure=vasprun.initial_structure,
             incar=dict(vasprun.incar),
@@ -217,18 +222,18 @@ class RunStatistics(BaseModel):
 class FrequencyDependentDielectric(BaseModel):
     """Frequency-dependent dielectric data."""
 
-    real: List[List[float]] = Field(
+    real: Optional[List[List[float]]] = Field(
         None,
         description="Real part of the frequency dependent dielectric constant, given at"
         " each energy as 6 components according to XX, YY, ZZ, XY, YZ, ZX",
     )
-    imaginary: List[List[float]] = Field(
+    imaginary: Optional[List[List[float]]] = Field(
         None,
         description="Imaginary part of the frequency dependent dielectric constant, "
         "given at each energy as 6 components according to XX, YY, ZZ, XY, "
         "YZ, ZX",
     )
-    energy: List[float] = Field(
+    energy: Optional[List[float]] = Field(
         None,
         description="Energies at which the real and imaginary parts of the dielectric"
         "constant are given",
@@ -256,12 +261,12 @@ class FrequencyDependentDielectric(BaseModel):
 class ElectronPhononDisplacedStructures(BaseModel):
     """Document defining electron phonon displaced structures."""
 
-    temperatures: List[float] = Field(
+    temperatures: Optional[List[float]] = Field(
         None,
         description="The temperatures at which the electron phonon displacements "
         "were generated.",
     )
-    structures: List[Structure] = Field(
+    structures: Optional[List[Structure]] = Field(
         None, description="The displaced structures corresponding to each temperature."
     )
 
@@ -272,121 +277,131 @@ class ElectronicStep(BaseModel, extra=Extra.allow):  # type: ignore
     Note, not all the information will be available at every step.
     """
 
-    alphaZ: float = Field(None, description="The alpha Z term.")
-    ewald: float = Field(None, description="The ewald energy.")
-    hartreedc: float = Field(None, description="Negative Hartree energy.")
-    XCdc: float = Field(None, description="Negative exchange energy.")
-    pawpsdc: float = Field(
+    alphaZ: Optional[float] = Field(None, description="The alpha Z term.")
+    ewald: Optional[float] = Field(None, description="The ewald energy.")
+    hartreedc: Optional[float] = Field(None, description="Negative Hartree energy.")
+    XCdc: Optional[float] = Field(None, description="Negative exchange energy.")
+    pawpsdc: Optional[float] = Field(
         None, description="Negative potential energy with exchange-correlation energy."
     )
-    pawaedc: float = Field(None, description="The PAW double counting term.")
-    eentropy: float = Field(None, description="The entropy (T * S).")
-    bandstr: float = Field(None, description="The band energy (from eigenvalues).")
-    atom: float = Field(None, description="The atomic energy.")
-    e_fr_energy: float = Field(None, description="The free energy.")
-    e_wo_entrp: float = Field(None, description="The energy without entropy.")
-    e_0_energy: float = Field(None, description="The internal energy.")
+    pawaedc: Optional[float] = Field(None, description="The PAW double counting term.")
+    eentropy: Optional[float] = Field(None, description="The entropy (T * S).")
+    bandstr: Optional[float] = Field(
+        None, description="The band energy (from eigenvalues)."
+    )
+    atom: Optional[float] = Field(None, description="The atomic energy.")
+    e_fr_energy: Optional[float] = Field(None, description="The free energy.")
+    e_wo_entrp: Optional[float] = Field(None, description="The energy without entropy.")
+    e_0_energy: Optional[float] = Field(None, description="The internal energy.")
 
 
 class IonicStep(BaseModel, extra=Extra.allow):  # type: ignore
     """Document defining the information at each ionic step."""
 
-    e_fr_energy: float = Field(None, description="The free energy.")
-    e_wo_entrp: float = Field(None, description="The energy without entropy.")
-    e_0_energy: float = Field(None, description="The internal energy.")
-    forces: List[Vector3D] = Field(None, description="The forces on each atom.")
-    stress: Matrix3D = Field(None, description="The stress on the lattice.")
-    electronic_steps: List[ElectronicStep] = Field(
+    e_fr_energy: Optional[float] = Field(None, description="The free energy.")
+    e_wo_entrp: Optional[float] = Field(None, description="The energy without entropy.")
+    e_0_energy: Optional[float] = Field(None, description="The internal energy.")
+    forces: Optional[List[Vector3D]] = Field(
+        None, description="The forces on each atom."
+    )
+    stress: Optional[Matrix3D] = Field(None, description="The stress on the lattice.")
+    electronic_steps: Optional[List[ElectronicStep]] = Field(
         None, description="The electronic convergence steps."
     )
-    structure: Structure = Field(None, description="The structure at this step.")
+    structure: Optional[Structure] = Field(
+        None, description="The structure at this step."
+    )
 
 
 class CalculationOutput(BaseModel):
     """Document defining VASP calculation outputs."""
 
-    energy: float = Field(
+    energy: Optional[float] = Field(
         None, description="The final total DFT energy for the calculation"
     )
-    energy_per_atom: float = Field(
+    energy_per_atom: Optional[float] = Field(
         None, description="The final DFT energy per atom for the calculation"
     )
-    structure: Structure = Field(
+    structure: Optional[Structure] = Field(
         None, description="The final structure from the calculation"
     )
-    efermi: float = Field(
+    efermi: Optional[float] = Field(
         None, description="The Fermi level from the calculation in eV"
     )
-    is_metal: bool = Field(None, description="Whether the system is metallic")
-    bandgap: float = Field(None, description="The band gap from the calculation in eV")
-    cbm: float = Field(
+    is_metal: Optional[bool] = Field(None, description="Whether the system is metallic")
+    bandgap: Optional[float] = Field(
+        None, description="The band gap from the calculation in eV"
+    )
+    cbm: Optional[float] = Field(
         None,
         description="The conduction band minimum in eV (if system is not metallic)",
     )
-    vbm: float = Field(
+    vbm: Optional[float] = Field(
         None, description="The valence band maximum in eV (if system is not metallic)"
     )
-    is_gap_direct: bool = Field(None, description="Whether the band gap is direct")
-    direct_gap: float = Field(
+    is_gap_direct: Optional[bool] = Field(
+        None, description="Whether the band gap is direct"
+    )
+    direct_gap: Optional[float] = Field(
         None, description="Direct band gap in eV (if system is not metallic)"
     )
-    transition: str = Field(
+    transition: Optional[str] = Field(
         None, description="Band gap transition given by CBM and VBM k-points"
     )
-    mag_density: float = Field(
+    mag_density: Optional[float] = Field(
         None,
         description="The magnetization density, defined as total_mag/volume "
         "(units of A^-3)",
     )
-    epsilon_static: ListMatrix3D = Field(
+    epsilon_static: Optional[ListMatrix3D] = Field(
         None, description="The high-frequency dielectric constant"
     )
-    epsilon_static_wolfe: ListMatrix3D = Field(
+    epsilon_static_wolfe: Optional[ListMatrix3D] = Field(
         None,
         description="The high-frequency dielectric constant w/o local field effects",
     )
-    epsilon_ionic: ListMatrix3D = Field(
+    epsilon_ionic: Optional[ListMatrix3D] = Field(
         None, description="The ionic part of the dielectric constant"
     )
-    frequency_dependent_dielectric: FrequencyDependentDielectric = Field(
+    frequency_dependent_dielectric: Optional[FrequencyDependentDielectric] = Field(
         None,
         description="Frequency-dependent dielectric information from an LOPTICS "
         "calculation",
     )
-    ionic_steps: List[IonicStep] = Field(
+    ionic_steps: Optional[List[IonicStep]] = Field(
         None, description="Energy, forces, structure, etc. for each ionic step"
     )
-    locpot: Dict[int, List[float]] = Field(
+    locpot: Optional[Dict[int, List[float]]] = Field(
         None, description="Average of the local potential along the crystal axes"
     )
-    outcar: Dict[str, Any] = Field(
+    outcar: Optional[Dict[str, Any]] = Field(
         None, description="Information extracted from the OUTCAR file"
     )
-    force_constants: List[List[Matrix3D]] = Field(
+    force_constants: Optional[List[List[Matrix3D]]] = Field(
         None, description="Force constants between every pair of atoms in the structure"
     )
-    normalmode_frequencies: List[float] = Field(
+    normalmode_frequencies: Optional[List[float]] = Field(
         None, description="Frequencies in THz of the normal modes at Gamma"
     )
-    normalmode_eigenvals: List[float] = Field(
+    normalmode_eigenvals: Optional[List[float]] = Field(
         None,
         description="Normal mode eigenvalues of phonon modes at Gamma. "
         "Note the unit changed between VASP 5 and 6.",
     )
-    normalmode_eigenvecs: List[List[Vector3D]] = Field(
+    normalmode_eigenvecs: Optional[List[List[Vector3D]]] = Field(
         None, description="Normal mode eigenvectors of phonon modes at Gamma"
     )
-    elph_displaced_structures: ElectronPhononDisplacedStructures = Field(
+    elph_displaced_structures: Optional[ElectronPhononDisplacedStructures] = Field(
         None,
         description="Electron-phonon displaced structures, generated by setting "
         "PHON_LMC = True.",
     )
-    dos_properties: Dict[str, Dict[str, Dict[str, float]]] = Field(
+    dos_properties: Optional[Dict[str, Dict[str, Dict[str, float]]]] = Field(
         None,
         description="Element- and orbital-projected band properties (in eV) for the "
         "DOS. All properties are with respect to the Fermi level.",
     )
-    run_stats: RunStatistics = Field(
+    run_stats: Optional[RunStatistics] = Field(
         None, description="Summary of runtime statistics for this calculation"
     )
 
@@ -538,36 +553,40 @@ class CalculationOutput(BaseModel):
 class Calculation(BaseModel):
     """Full VASP calculation inputs and outputs."""
 
-    dir_name: str = Field(None, description="The directory for this VASP calculation")
-    vasp_version: str = Field(
+    dir_name: Optional[str] = Field(
+        None, description="The directory for this VASP calculation"
+    )
+    vasp_version: Optional[str] = Field(
         None, description="VASP version used to perform the calculation"
     )
-    has_vasp_completed: Union[TaskState, bool] = Field(
+    has_vasp_completed: Optional[Union[TaskState, bool]] = Field(
         None, description="Whether VASP completed the calculation successfully"
     )
-    input: CalculationInput = Field(
+    input: Optional[CalculationInput] = Field(
         None, description="VASP input settings for the calculation"
     )
-    output: CalculationOutput = Field(None, description="The VASP calculation output")
-    completed_at: str = Field(
+    output: Optional[CalculationOutput] = Field(
+        None, description="The VASP calculation output"
+    )
+    completed_at: Optional[str] = Field(
         None, description="Timestamp for when the calculation was completed"
     )
-    task_name: str = Field(
+    task_name: Optional[str] = Field(
         None, description="Name of task given by custodian (e.g., relax1, relax2)"
     )
-    output_file_paths: Dict[str, str] = Field(
+    output_file_paths: Optional[Dict[str, str]] = Field(
         None,
         description="Paths (relative to dir_name) of the VASP output files "
         "associated with this calculation",
     )
-    bader: Dict = Field(None, description="Output from the bader software")
-    run_type: RunType = Field(
+    bader: Optional[dict] = Field(None, description="Output from the bader software")
+    run_type: Optional[RunType] = Field(
         None, description="Calculation run type (e.g., HF, HSE06, PBE)"
     )
-    task_type: TaskType = Field(
+    task_type: Optional[TaskType] = Field(
         None, description="Calculation task type (e.g., Structure Optimization)."
     )
-    calc_type: CalcType = Field(
+    calc_type: Optional[CalcType] = Field(
         None, description="Return calculation type (run type + task_type)."
     )
 
@@ -711,7 +730,9 @@ class Calculation(BaseModel):
         if store_trajectory:
             traj = Trajectory.from_structures(
                 [d["structure"] for d in vasprun.ionic_steps],
-                frame_properties=[IonicStep(**x).dict() for x in vasprun.ionic_steps],
+                frame_properties=[
+                    IonicStep(**x).model_dump() for x in vasprun.ionic_steps
+                ],
                 constant_lattice=False,
             )
             vasp_objects[VaspObject.TRAJECTORY] = traj  # type: ignore
@@ -742,8 +763,8 @@ class Calculation(BaseModel):
                 },
                 bader=bader,
                 run_type=run_type(input_doc.parameters),
-                task_type=task_type(input_doc.dict()),
-                calc_type=calc_type(input_doc.dict(), input_doc.parameters),
+                task_type=task_type(input_doc.model_dump()),
+                calc_type=calc_type(input_doc.model_dump(), input_doc.parameters),
             ),
             vasp_objects,
         )
@@ -808,8 +829,8 @@ class Calculation(BaseModel):
             output=output_doc,
             output_file_paths={},
             run_type=run_type(input_doc.parameters),
-            task_type=task_type(input_doc.dict()),
-            calc_type=calc_type(input_doc.dict(), input_doc.parameters),
+            task_type=task_type(input_doc.model_dump()),
+            calc_type=calc_type(input_doc.model_dump(), input_doc.parameters),
         )
 
 
diff --git a/emmet-core/emmet/core/vasp/material.py b/emmet-core/emmet/core/vasp/material.py
index c3d8c14..611c26e 100644
--- a/emmet-core/emmet/core/vasp/material.py
+++ b/emmet-core/emmet/core/vasp/material.py
@@ -1,5 +1,5 @@
 """ Core definition of a Materials Document """
-from typing import Dict, List, Mapping
+from typing import Dict, List, Mapping, Optional
 
 from pydantic import Field
 from pymatgen.analysis.structure_analyzer import SpacegroupAnalyzer
@@ -21,20 +21,20 @@ class MaterialsDoc(CoreMaterialsDoc, StructureMetadata):
         None,
         description="Calculation types for all the calculations that make up this material",
     )
-    task_types: Mapping[str, TaskType] = Field(
+    task_types: Optional[Mapping[str, TaskType]] = Field(
         None,
         description="Task types for all the calculations that make up this material",
     )
-    run_types: Mapping[str, RunType] = Field(
+    run_types: Optional[Mapping[str, RunType]] = Field(
         None,
         description="Run types for all the calculations that make up this material",
     )
 
-    origins: List[PropertyOrigin] = Field(
+    origins: Optional[List[PropertyOrigin]] = Field(
         None, description="Mappingionary for tracking the provenance of properties"
     )
 
-    entries: Mapping[RunType, ComputedStructureEntry] = Field(
+    entries: Optional[Mapping[RunType, ComputedStructureEntry]] = Field(
         None, description="Dictionary for tracking entries for VASP calculations"
     )
 
diff --git a/emmet-core/emmet/core/vasp/task_valid.py b/emmet-core/emmet/core/vasp/task_valid.py
index 9861e1e..4702ee1 100644
--- a/emmet-core/emmet/core/vasp/task_valid.py
+++ b/emmet-core/emmet/core/vasp/task_valid.py
@@ -1,7 +1,7 @@
 # mypy: ignore-errors
 
 """ Core definition of a VASP Task Document """
-from typing import Any, Dict, List, Union
+from typing import Any, Dict, List, Union, Optional
 
 from pydantic import BaseModel, Field
 from pymatgen.analysis.structure_analyzer import oxide_type
@@ -30,7 +30,9 @@ class InputSummary(BaseModel):
     Summary of inputs for a VASP calculation
     """
 
-    structure: Structure = Field(None, description="The input structure object")
+    structure: Optional[Structure] = Field(
+        None, description="The input structure object"
+    )
     parameters: Dict = Field(
         {},
         description="Input parameters from VASPRUN for the last calculation in the series",
@@ -53,14 +55,18 @@ class OutputSummary(BaseModel):
     Summary of the outputs for a VASP calculation
     """
 
-    structure: Structure = Field(None, description="The output structure object")
-    energy: float = Field(
+    structure: Optional[Structure] = Field(
+        None, description="The output structure object"
+    )
+    energy: Optional[float] = Field(
         None, description="The final total DFT energy for the last calculation"
     )
-    energy_per_atom: float = Field(
+    energy_per_atom: Optional[float] = Field(
         None, description="The final DFT energy per atom for the last calculation"
     )
-    bandgap: float = Field(None, description="The DFT bandgap for the last calculation")
+    bandgap: Optional[float] = Field(
+        None, description="The DFT bandgap for the last calculation"
+    )
     forces: List[Vector3D] = Field(
         [], description="Forces on atoms from the last calculation"
     )
@@ -74,17 +80,25 @@ class RunStatistics(BaseModel):
     Summary of the Run statistics for a VASP calculation
     """
 
-    average_memory: float = Field(None, description="The average memory used in kb")
-    max_memory: float = Field(None, description="The maximum memory used in kb")
-    elapsed_time: float = Field(None, description="The real time elapsed in seconds")
-    system_time: float = Field(None, description="The system CPU time in seconds")
-    user_time: float = Field(
+    average_memory: Optional[float] = Field(
+        None, description="The average memory used in kb"
+    )
+    max_memory: Optional[float] = Field(
+        None, description="The maximum memory used in kb"
+    )
+    elapsed_time: Optional[float] = Field(
+        None, description="The real time elapsed in seconds"
+    )
+    system_time: Optional[float] = Field(
+        None, description="The system CPU time in seconds"
+    )
+    user_time: Optional[float] = Field(
         None, description="The user CPU time spent by VASP in seconds"
     )
-    total_time: float = Field(
+    total_time: Optional[float] = Field(
         None, description="The total CPU time for this calculation"
     )
-    cores: Union[int, str] = Field(
+    cores: Optional[Union[int, str]] = Field(
         None,
         description="The number of cores used by VASP (some clusters print `mpi-ranks` here)",
     )
@@ -95,7 +109,7 @@ class TaskDocument(BaseTaskDocument, StructureMetadata):
     Definition of VASP Task Document
     """
 
-    calc_code = "VASP"
+    calc_code: str = "VASP"
     run_stats: Dict[str, RunStatistics] = Field(
         {},
         description="Summary of runtime statistics for each calculation in this task",
@@ -108,7 +122,7 @@ class TaskDocument(BaseTaskDocument, StructureMetadata):
     input: InputSummary = Field(InputSummary())
     output: OutputSummary = Field(OutputSummary())
 
-    state: TaskState = Field(None, description="State of this calculation")
+    state: Optional[TaskState] = Field(None, description="State of this calculation")
 
     orig_inputs: Dict[str, Any] = Field(
         {}, description="Summary of the original VASP inputs"
@@ -122,7 +136,7 @@ class TaskDocument(BaseTaskDocument, StructureMetadata):
         [], description="Metadata tags for this task document"
     )
 
-    warnings: List[str] = Field(
+    warnings: Optional[List[str]] = Field(
         None, description="Any warnings related to this property"
     )
 
diff --git a/emmet-core/emmet/core/vasp/validation.py b/emmet-core/emmet/core/vasp/validation.py
index 65c21eb..1d278f2 100644
--- a/emmet-core/emmet/core/vasp/validation.py
+++ b/emmet-core/emmet/core/vasp/validation.py
@@ -2,7 +2,7 @@ from datetime import datetime
 from typing import Dict, List, Union, Optional
 
 import numpy as np
-from pydantic import Field, PyObject
+from pydantic import ConfigDict, Field, ImportString
 from pymatgen.core.structure import Structure
 from pymatgen.io.vasp.sets import VaspInputSet
 
@@ -45,7 +45,7 @@ class ValidationDoc(EmmetBaseModel):
         description="Last updated date for this document",
         default_factory=datetime.utcnow,
     )
-    reasons: List[Union[DeprecationMessage, str]] = Field(
+    reasons: Optional[List[Union[DeprecationMessage, str]]] = Field(
         None, description="List of deprecation tags detailing why this task isn't valid"
     )
     warnings: List[str] = Field(
@@ -55,9 +55,7 @@ class ValidationDoc(EmmetBaseModel):
         description="Dictioary of data used to perform validation."
         " Useful for post-mortem analysis"
     )
-
-    class Config:
-        extra = "allow"
+    model_config = ConfigDict(extra="allow")
 
     @classmethod
     def from_task_doc(
@@ -65,7 +63,7 @@ class ValidationDoc(EmmetBaseModel):
         task_doc: TaskDocument,
         kpts_tolerance: float = SETTINGS.VASP_KPTS_TOLERANCE,
         kspacing_tolerance: float = SETTINGS.VASP_KSPACING_TOLERANCE,
-        input_sets: Dict[str, PyObject] = SETTINGS.VASP_DEFAULT_INPUT_SETS,
+        input_sets: Dict[str, ImportString] = SETTINGS.VASP_DEFAULT_INPUT_SETS,
         LDAU_fields: List[str] = SETTINGS.VASP_CHECKED_LDAU_FIELDS,
         max_allowed_scf_gradient: float = SETTINGS.VASP_MAX_SCF_GRADIENT,
         potcar_hashes: Optional[Dict[CalcType, Dict[str, str]]] = None,
diff --git a/emmet-core/emmet/core/xas.py b/emmet-core/emmet/core/xas.py
index e3cec26..f9f0bc5 100644
--- a/emmet-core/emmet/core/xas.py
+++ b/emmet-core/emmet/core/xas.py
@@ -48,7 +48,7 @@ class XASDoc(SpectrumDoc):
     Document describing a XAS Spectrum.
     """
 
-    spectrum_name = "XAS"
+    spectrum_name: str = "XAS"
 
     spectrum: XAS
 
diff --git a/emmet-core/emmet/core/xrd.py b/emmet-core/emmet/core/xrd.py
index 645c2da..67fc4f2 100644
--- a/emmet-core/emmet/core/xrd.py
+++ b/emmet-core/emmet/core/xrd.py
@@ -1,7 +1,7 @@
-from typing import Dict
+from typing import Dict, Optional
 
 import numpy as np
-from pydantic import Field, root_validator
+from pydantic import model_validator, Field
 from pymatgen.analysis.diffraction.xrd import (
     WAVELENGTHS,
     DiffractionPattern,
@@ -29,18 +29,21 @@ class XRDDoc(SpectrumDoc):
     Document describing a XRD Diffraction Pattern
     """
 
-    spectrum_name = "XRD"
+    spectrum_name: str = "XRD"
 
     spectrum: DiffractionPattern
     min_two_theta: float
     max_two_theta: float
     wavelength: float = Field(..., description="Wavelength for the diffraction source.")
-    target: Element = Field(
+    target: Optional[Element] = Field(
         None, description="Target element for the diffraction source."
     )
-    edge: Edge = Field(None, description="Atomic edge for the diffraction source.")
+    edge: Optional[Edge] = Field(
+        None, description="Atomic edge for the diffraction source."
+    )
 
-    @root_validator(pre=True)
+    @model_validator(mode="before")
+    @classmethod
     def get_target_and_edge(cls, values: Dict):
         print("Validations")
         # Only do this if neither target not edge is defined
COLLAB_REFERENCE_PATCH_EOF
