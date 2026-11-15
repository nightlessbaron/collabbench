#!/bin/bash
set -euo pipefail
cd "${WORKSPACE:-/workspace}"
git apply --whitespace=nowarn <<'COLLAB_REFERENCE_PATCH_EOF'
diff --git a/ormar/__init__.py b/ormar/__init__.py
index 9259d1d..ea4a49c 100644
--- a/ormar/__init__.py
+++ b/ormar/__init__.py
@@ -19,11 +19,10 @@ snakes, and ormar(e) in italian which means cabinet.
 And what's a better name for python ORM than snakes cabinet :)
 
 """
-try:
-    from importlib.metadata import version  # type: ignore
-except ImportError:  # pragma: no cover
-    from importlib_metadata import version  # type: ignore
-from ormar.protocols import QuerySetProtocol, RelationProtocol  # noqa: I100
+
+from ormar.protocols import QuerySetProtocol, RelationProtocol  # noqa: I001
+from importlib.metadata import version
+
 from ormar.decorators import (  # noqa: I100
     post_bulk_update,
     post_delete,
@@ -36,7 +35,6 @@ from ormar.decorators import (  # noqa: I100
     pre_relation_remove,
     pre_save,
     pre_update,
-    property_field,
 )
 from ormar.exceptions import (  # noqa: I100
     ModelDefinitionError,
@@ -44,37 +42,38 @@ from ormar.exceptions import (  # noqa: I100
     NoMatch,
 )
 from ormar.fields import (
+    DECODERS_MAP,
+    ENCODERS_MAP,
+    JSON,
+    SQL_ENCODERS_MAP,
+    UUID,
     BaseField,
     BigInteger,
     Boolean,
-    DECODERS_MAP,
+    CheckColumns,
     Date,
     DateTime,
     Decimal,
-    ENCODERS_MAP,
     EncryptBackends,
     Enum,
     Float,
     ForeignKey,
     ForeignKeyField,
+    IndexColumns,
     Integer,
-    JSON,
     LargeBinary,
     ManyToMany,
     ManyToManyField,
-    SQL_ENCODERS_MAP,
+    ReferentialAction,
     SmallInteger,
     String,
     Text,
     Time,
-    UUID,
     UniqueColumns,
-    IndexColumns,
-    CheckColumns,
-    ReferentialAction,
-)  # noqa: I100
-from ormar.models import ExcludableItems, Extra, Model
-from ormar.models.metaclass import ModelMeta
+)
+
+# noqa: I100
+from ormar.models import ExcludableItems, Extra, Model, OrmarConfig
 from ormar.queryset import OrderAction, QuerySet, and_, or_
 from ormar.relations import RelationType
 from ormar.signals import Signal
@@ -104,7 +103,6 @@ __all__ = [
     "Float",
     "ManyToMany",
     "Model",
-    "Action",
     "ModelDefinitionError",
     "MultipleMatches",
     "NoMatch",
@@ -119,8 +117,6 @@ __all__ = [
     "ReferentialAction",
     "QuerySetProtocol",
     "RelationProtocol",
-    "ModelMeta",
-    "property_field",
     "post_bulk_update",
     "post_delete",
     "post_save",
@@ -146,4 +142,9 @@ __all__ = [
     "DECODERS_MAP",
     "LargeBinary",
     "Extra",
+    "OrmarConfig",
+    "ModelMeta",
 ]
+
+# Kept so that downstream type hints that import the old name keep working.
+ModelMeta = OrmarConfig
diff --git a/ormar/decorators/__init__.py b/ormar/decorators/__init__.py
index c6f42d0..04005f2 100644
--- a/ormar/decorators/__init__.py
+++ b/ormar/decorators/__init__.py
@@ -3,11 +3,10 @@ Module with all decorators that are exposed for users.
 
 Currently only:
 
-* property_field - exposing @property like function as field in Model.dict()
 * predefined signals decorators (pre/post + save/update/delete)
 
 """
-from ormar.decorators.property_field import property_field
+
 from ormar.decorators.signals import (
     post_bulk_update,
     post_delete,
@@ -23,7 +22,6 @@ from ormar.decorators.signals import (
 )
 
 __all__ = [
-    "property_field",
     "post_bulk_update",
     "post_delete",
     "post_save",
diff --git a/ormar/decorators/property_field.py b/ormar/decorators/property_field.py
deleted file mode 100644
index 69ec9da..0000000
--- a/ormar/decorators/property_field.py
+++ /dev/null
@@ -1,32 +0,0 @@
-import inspect
-from collections.abc import Callable
-from typing import Union
-
-from ormar.exceptions import ModelDefinitionError
-
-
-def property_field(func: Callable) -> Union[property, Callable]:
-    """
-    Decorator to set a property like function on Model to be exposed
-    as field in dict() and fastapi response.
-    Although you can decorate a @property field like this and this will work,
-    mypy validation will complain about this.
-    Note that "fields" exposed like this do not go through validation.
-
-    :raises ModelDefinitionError: if method has any other argument than self.
-    :param func: decorated function to be exposed
-    :type func: Callable
-    :return: decorated function passed in func param, with set __property_field__ = True
-    :rtype: Union[property, Callable]
-    """
-    if isinstance(func, property):  # pragma: no cover
-        func.fget.__property_field__ = True
-    else:
-        arguments = list(inspect.signature(func).parameters.keys())
-        if len(arguments) > 1 or arguments[0] != "self":
-            raise ModelDefinitionError(
-                "property_field decorator can be used "
-                "only on methods with no arguments"
-            )
-        func.__dict__["__property_field__"] = True
-    return func
diff --git a/ormar/decorators/signals.py b/ormar/decorators/signals.py
index 3e10c1d..b3b38b9 100644
--- a/ormar/decorators/signals.py
+++ b/ormar/decorators/signals.py
@@ -1,4 +1,4 @@
-from typing import Callable, List, TYPE_CHECKING, Type, Union
+from typing import TYPE_CHECKING, Callable, List, Type, Union
 
 if TYPE_CHECKING:  # pragma: no cover
     from ormar import Model
@@ -34,7 +34,7 @@ def receiver(
         else:
             _senders = senders
         for sender in _senders:
-            signals = getattr(sender.Meta.signals, signal)
+            signals = getattr(sender.ormar_config.signals, signal)
             signals.connect(func)
         return func
 
diff --git a/ormar/exceptions.py b/ormar/exceptions.py
index 12e2e3a..d7e56d1 100644
--- a/ormar/exceptions.py
+++ b/ormar/exceptions.py
@@ -15,11 +15,9 @@ class ModelDefinitionError(AsyncOrmException):
     """
     Raised for errors related to the model definition itself:
 
-    * setting @property_field on method with arguments other than func(self)
     * defining a Field without required parameters
     * defining a model with more than one primary_key
     * defining a model without primary_key
-    * setting primary_key column as pydantic_only
     """
 
     pass
diff --git a/ormar/fields/__init__.py b/ormar/fields/__init__.py
index 08fec4f..84d2acb 100644
--- a/ormar/fields/__init__.py
+++ b/ormar/fields/__init__.py
@@ -4,11 +4,14 @@ Base Fields types (like String, Integer etc.)
 as well as relation Fields (ForeignKey, ManyToMany).
 Also a definition for custom CHAR based sqlalchemy UUID field
 """
+
 from ormar.fields.base import BaseField
-from ormar.fields.constraints import IndexColumns, UniqueColumns, CheckColumns
+from ormar.fields.constraints import CheckColumns, IndexColumns, UniqueColumns
 from ormar.fields.foreign_key import ForeignKey, ForeignKeyField
 from ormar.fields.many_to_many import ManyToMany, ManyToManyField
 from ormar.fields.model_fields import (
+    JSON,
+    UUID,
     BigInteger,
     Boolean,
     Date,
@@ -17,18 +20,16 @@ from ormar.fields.model_fields import (
     Enum,
     Float,
     Integer,
-    JSON,
     LargeBinary,
     SmallInteger,
     String,
     Text,
     Time,
-    UUID,
 )
 from ormar.fields.parsers import DECODERS_MAP, ENCODERS_MAP, SQL_ENCODERS_MAP
+from ormar.fields.referential_actions import ReferentialAction
 from ormar.fields.sqlalchemy_encrypted import EncryptBackend, EncryptBackends
 from ormar.fields.through_field import Through, ThroughField
-from ormar.fields.referential_actions import ReferentialAction
 
 __all__ = [
     "Decimal",
diff --git a/ormar/fields/base.py b/ormar/fields/base.py
index f7eaff5..a55f9a9 100644
--- a/ormar/fields/base.py
+++ b/ormar/fields/base.py
@@ -1,9 +1,7 @@
-import warnings
-from typing import Any, Dict, List, Optional, TYPE_CHECKING, Type, Union
+from typing import TYPE_CHECKING, Any, Dict, List, Optional, Type, Union
 
 import sqlalchemy
-from pydantic import Json, typing
-from pydantic.fields import FieldInfo, Required, Undefined
+from pydantic.fields import FieldInfo, _Unset
 
 import ormar  # noqa I101
 from ormar import ModelDefinitionError
@@ -14,8 +12,7 @@ from ormar.fields.sqlalchemy_encrypted import (
 )
 
 if TYPE_CHECKING:  # pragma no cover
-    from ormar.models import Model
-    from ormar.models import NewBaseModel
+    from ormar.models import Model, NewBaseModel
 
 
 class BaseField(FieldInfo):
@@ -46,16 +43,6 @@ class BaseField(FieldInfo):
         self.sql_nullable: bool = kwargs.pop("sql_nullable", False)
         self.index: bool = kwargs.pop("index", False)
         self.unique: bool = kwargs.pop("unique", False)
-        self.pydantic_only: bool = kwargs.pop("pydantic_only", False)
-        if self.pydantic_only:
-            warnings.warn(
-                "Parameter `pydantic_only` is deprecated and will "
-                "be removed in one of the next releases.\n You can declare "
-                "pydantic fields in a normal way. \n Check documentation: "
-                "https://collerek.github.io/ormar/fields/pydantic-fields",
-                DeprecationWarning,
-            )
-        self.choices: typing.Sequence = kwargs.pop("choices", False)
 
         self.virtual: bool = kwargs.pop(
             "virtual", None
@@ -76,6 +63,7 @@ class BaseField(FieldInfo):
 
         self.owner: Type["Model"] = kwargs.pop("owner", None)
         self.to: Type["Model"] = kwargs.pop("to", None)
+        self.to_pk_only: Type["Model"] = kwargs.pop("to_pk_only", None)
         self.through: Type["Model"] = kwargs.pop("through", None)
         self.self_reference: bool = kwargs.pop("self_reference", False)
         self.self_reference_primary: Optional[str] = kwargs.pop(
@@ -145,9 +133,7 @@ class BaseField(FieldInfo):
         """
         base = self.default_value()
         if base is None:
-            base = dict(default=None) if self.nullable else dict(default=Undefined)
-        if self.__type__ == Json and base.get("default") is Undefined:
-            base["default"] = Required
+            base = dict(default=None) if self.nullable else dict(default=_Unset)
         return base
 
     def default_value(self, use_server: bool = False) -> Optional[Dict]:
@@ -181,7 +167,9 @@ class BaseField(FieldInfo):
             return dict(default=default)
         return None
 
-    def get_default(self, use_server: bool = False) -> Any:  # noqa CCR001
+    def get_default(
+        self, use_server: bool = False, call_default_factory: bool = True
+    ) -> Any:  # noqa CCR001
         """
         Return default value for a field.
         If the field is Callable the function is called and actual result is returned.
@@ -197,11 +185,26 @@ class BaseField(FieldInfo):
             default = (
                 self.ormar_default
                 if self.ormar_default is not None
-                else (self.server_default if use_server else None)
+                else self._get_default_server_value(use_server=use_server)
+            )
+            return self._get_default_callable_value(
+                default=default,
+                call_default_factory=call_default_factory,
             )
-            if callable(default):  # pragma: no cover
-                default = default()
-            return default
+
+    def _get_default_server_value(self, use_server: bool) -> Any:
+        """
+        Return default value for a server side if use_server is True
+        """
+        return self.server_default if use_server else None
+
+    @staticmethod
+    def _get_default_callable_value(default: Any, call_default_factory: bool) -> Any:
+        """
+        Return default factory value if call_default_factory is True
+        and default is a callable.
+        """
+        return default() if (callable(default) and call_default_factory) else default
 
     def has_default(self, use_server: bool = True) -> bool:
         """
@@ -244,8 +247,8 @@ class BaseField(FieldInfo):
                 con.reference,
                 ondelete=con.ondelete,
                 onupdate=con.onupdate,
-                name=f"fk_{self.owner.Meta.tablename}_{self.to.Meta.tablename}"
-                f"_{self.to.get_column_alias(self.to.Meta.pkname)}_{self.name}",
+                name=f"fk_{self.owner.ormar_config.tablename}_{self.to.ormar_config.tablename}"
+                f"_{self.to.get_column_alias(self.to.ormar_config.pkname)}_{self.name}",
             )
             for con in self.constraints
         ]
@@ -339,7 +342,7 @@ class BaseField(FieldInfo):
         :rtype: None
         """
         if self.owner is not None and (
-            self.owner == self.to or self.owner.Meta == self.to.Meta
+            self.owner == self.to or self.owner.ormar_config == self.to.ormar_config
         ):
             self.self_reference = True
             self.self_reference_primary = self.name
diff --git a/ormar/fields/constraints.py b/ormar/fields/constraints.py
index e799d0c..66a90f0 100644
--- a/ormar/fields/constraints.py
+++ b/ormar/fields/constraints.py
@@ -1,6 +1,6 @@
-from typing import Any
+from typing import Any, Optional
 
-from sqlalchemy import Index, UniqueConstraint, CheckConstraint
+from sqlalchemy import CheckConstraint, Index, UniqueConstraint
 
 
 class UniqueColumns(UniqueConstraint):
@@ -11,7 +11,7 @@ class UniqueColumns(UniqueConstraint):
 
 
 class IndexColumns(Index):
-    def __init__(self, *args: Any, name: str = None, **kw: Any) -> None:
+    def __init__(self, *args: Any, name: Optional[str] = None, **kw: Any) -> None:
         if not name:
             name = "TEMPORARY_NAME"
         super().__init__(name, *args, **kw)
diff --git a/ormar/fields/foreign_key.py b/ormar/fields/foreign_key.py
index cfa2205..a867c39 100644
--- a/ormar/fields/foreign_key.py
+++ b/ormar/fields/foreign_key.py
@@ -1,30 +1,32 @@
 import string
+import sys
 import uuid
 from dataclasses import dataclass
 from random import choices
 from typing import (
+    TYPE_CHECKING,
     Any,
     Dict,
+    ForwardRef,
     List,
     Optional,
-    TYPE_CHECKING,
     Tuple,
     Type,
     Union,
     overload,
 )
 
-import ormar  # noqa I101
 import sqlalchemy
+from pydantic import BaseModel, create_model
+
+import ormar  # noqa I101
 from ormar.exceptions import ModelDefinitionError, RelationshipInstanceError
 from ormar.fields.base import BaseField
 from ormar.fields.referential_actions import ReferentialAction
-from pydantic import BaseModel, create_model
-from pydantic.typing import ForwardRef, evaluate_forwardref
 
 if TYPE_CHECKING:  # pragma no cover
-    from ormar.models import Model, NewBaseModel, T
     from ormar.fields import ManyToManyField
+    from ormar.models import Model, NewBaseModel, T
 
 
 def create_dummy_instance(fk: Type["T"], pk: Any = None) -> "T":
@@ -47,10 +49,10 @@ def create_dummy_instance(fk: Type["T"], pk: Any = None) -> "T":
     :rtype: Model
     """
     init_dict = {
-        **{fk.Meta.pkname: pk or -1, "__pk_only__": True},
+        **{fk.ormar_config.pkname: pk or -1, "__pk_only__": True},
         **{
             k: create_dummy_instance(v.to)
-            for k, v in fk.Meta.model_fields.items()
+            for k, v in fk.ormar_config.model_fields.items()
             if v.is_relation and not v.nullable and not v.virtual
         },
     }
@@ -86,8 +88,11 @@ def create_dummy_model(
 
 
 def populate_fk_params_based_on_to_model(
-    to: Type["T"], nullable: bool, onupdate: str = None, ondelete: str = None
-) -> Tuple[Any, List, Any]:
+    to: Type["T"],
+    nullable: bool,
+    onupdate: Optional[str] = None,
+    ondelete: Optional[str] = None,
+) -> Tuple[Any, List, Any, Any]:
     """
     Based on target to model to which relation leads to populates the type of the
     pydantic field to use, ForeignKey constraint and type of the target column field.
@@ -105,8 +110,10 @@ def populate_fk_params_based_on_to_model(
     :return: tuple with target pydantic type, list of fk constraints and target col type
     :rtype: Tuple[Any, List, Any]
     """
-    fk_string = to.Meta.tablename + "." + to.get_column_alias(to.Meta.pkname)
-    to_field = to.Meta.model_fields[to.Meta.pkname]
+    fk_string = (
+        to.ormar_config.tablename + "." + to.get_column_alias(to.ormar_config.pkname)
+    )
+    to_field = to.ormar_config.model_fields[to.ormar_config.pkname]
     pk_only_model = create_dummy_model(to, to_field)
     __type__ = (
         Union[to_field.__type__, to, pk_only_model]
@@ -119,7 +126,7 @@ def populate_fk_params_based_on_to_model(
         )
     ]
     column_type = to_field.column_type
-    return __type__, constraints, column_type
+    return __type__, constraints, column_type, pk_only_model
 
 
 def validate_not_allowed_fields(kwargs: Dict) -> None:
@@ -200,13 +207,13 @@ def ForeignKey(to: ForwardRef, **kwargs: Any) -> "Model":  # pragma: no cover
 def ForeignKey(  # type: ignore # noqa CFQ002
     to: Union[Type["T"], "ForwardRef"],
     *,
-    name: str = None,
+    name: Optional[str] = None,
     unique: bool = False,
     nullable: bool = True,
-    related_name: str = None,
+    related_name: Optional[str] = None,
     virtual: bool = False,
-    onupdate: Union[ReferentialAction, str] = None,
-    ondelete: Union[ReferentialAction, str] = None,
+    onupdate: Union[ReferentialAction, str, None] = None,
+    ondelete: Union[ReferentialAction, str, None] = None,
     **kwargs: Any,
 ) -> "T":
     """
@@ -256,13 +263,18 @@ def ForeignKey(  # type: ignore # noqa CFQ002
     sql_nullable = nullable if sql_nullable is None else sql_nullable
 
     validate_not_allowed_fields(kwargs)
-
+    pk_only_model = None
     if to.__class__ == ForwardRef:
         __type__ = to if not nullable else Optional[to]
         constraints: List = []
         column_type = None
     else:
-        __type__, constraints, column_type = populate_fk_params_based_on_to_model(
+        (
+            __type__,
+            constraints,
+            column_type,
+            pk_only_model,
+        ) = populate_fk_params_based_on_to_model(
             to=to,  # type: ignore
             nullable=nullable,
             ondelete=ondelete,
@@ -272,6 +284,7 @@ def ForeignKey(  # type: ignore # noqa CFQ002
     namespace = dict(
         __type__=__type__,
         to=to,
+        to_pk_only=pk_only_model,
         through=None,
         alias=name,
         name=kwargs.pop("real_name", None),
@@ -284,7 +297,6 @@ def ForeignKey(  # type: ignore # noqa CFQ002
         virtual=virtual,
         primary_key=False,
         index=False,
-        pydantic_only=False,
         default=None,
         server_default=None,
         onupdate=onupdate,
@@ -352,6 +364,17 @@ class ForeignKeyField(BaseField):
         prefix = "to_" if self.self_reference else ""
         return self.through_relation_name or f"{prefix}{self.owner.get_name()}"
 
+    def _evaluate_forward_ref(
+        self, globalns: Any, localns: Any, is_through: bool = False
+    ) -> None:
+        target = "through" if is_through else "to"
+        target_obj = getattr(self, target)
+        if sys.version_info.minor <= 8:  # pragma: no cover
+            evaluated = target_obj._evaluate(globalns, localns)
+        else:  # pragma: no cover
+            evaluated = target_obj._evaluate(globalns, localns, set())
+        setattr(self, target, evaluated)
+
     def evaluate_forward_ref(self, globalns: Any, localns: Any) -> None:
         """
         Evaluates the ForwardRef to actual Field based on global and local namespaces
@@ -364,13 +387,12 @@ class ForeignKeyField(BaseField):
         :rtype: None
         """
         if self.to.__class__ == ForwardRef:
-            self.to = evaluate_forwardref(
-                self.to, globalns, localns or None  # type: ignore
-            )
+            self._evaluate_forward_ref(globalns, localns)
             (
                 self.__type__,
                 self.constraints,
                 self.column_type,
+                self.to_pk_only,
             ) = populate_fk_params_based_on_to_model(
                 to=self.to,
                 nullable=self.nullable,
@@ -444,12 +466,21 @@ class ForeignKeyField(BaseField):
         :return: (if needed) registered Model
         :rtype: Model
         """
-        if len(value.keys()) == 1 and list(value.keys())[0] == self.to.Meta.pkname:
+        pk_only_model = None
+        keys = set(value.keys())
+        own_keys = keys - self.to.extract_related_names()
+        if (
+            len(own_keys) == 1
+            and list(own_keys)[0] == self.to.ormar_config.pkname
+            and value.get(self.to.ormar_config.pkname) is not None
+            and not self.is_through
+        ):
             value["__pk_only__"] = True
+            pk_only_model = self.to_pk_only(**value)
         model = self.to(**value)
         if to_register:
             self.register_relation(model=model, child=child)
-        return model
+        return pk_only_model if pk_only_model is not None else model
 
     def _construct_model_from_pk(
         self, value: Any, child: "Model", to_register: bool
@@ -472,11 +503,14 @@ class ForeignKeyField(BaseField):
         if self.to.pk_type() == uuid.UUID and isinstance(value, str):  # pragma: nocover
             value = uuid.UUID(value)
         if not isinstance(value, self.to.pk_type()):
-            raise RelationshipInstanceError(
-                f"Relationship error - ForeignKey {self.to.__name__} "
-                f"is of type {self.to.pk_type()} "
-                f"while {type(value)} passed as a parameter."
-            )
+            if isinstance(value, self.to_pk_only):
+                value = getattr(value, self.to.ormar_config.pkname)
+            else:
+                raise RelationshipInstanceError(
+                    f"Relationship error - ForeignKey {self.to.__name__} "
+                    f"is of type {self.to.pk_type()} "
+                    f"while {type(value)} passed as a parameter."
+                )
         model = create_dummy_instance(fk=self.to, pk=value)
         if to_register:
             self.register_relation(model=model, child=child)
diff --git a/ormar/fields/many_to_many.py b/ormar/fields/many_to_many.py
index 350fa3c..1a8af2d 100644
--- a/ormar/fields/many_to_many.py
+++ b/ormar/fields/many_to_many.py
@@ -1,9 +1,9 @@
-import sys
 from typing import (
+    TYPE_CHECKING,
     Any,
+    ForwardRef,
     List,
     Optional,
-    TYPE_CHECKING,
     Tuple,
     Type,
     Union,
@@ -11,21 +11,19 @@ from typing import (
     overload,
 )
 
-from pydantic.typing import ForwardRef, evaluate_forwardref
 import ormar  # noqa: I100
 from ormar import ModelDefinitionError
 from ormar.fields import BaseField
-from ormar.fields.foreign_key import ForeignKeyField, validate_not_allowed_fields
+from ormar.fields.foreign_key import (
+    ForeignKeyField,
+    create_dummy_model,
+    validate_not_allowed_fields,
+)
 
 if TYPE_CHECKING:  # pragma no cover
     from ormar.models import Model, T
     from ormar.relations.relation_proxy import RelationProxy
 
-    if sys.version_info < (3, 7):
-        ToType = Type["T"]
-    else:
-        ToType = Union[Type["T"], "ForwardRef"]
-
 REF_PREFIX = "#/components/schemas/"
 
 
@@ -36,7 +34,7 @@ def forbid_through_relations(through: Type["Model"]) -> None:
     :param through: through Model to be checked
     :type through: Type['Model]
     """
-    if any(field.is_relation for field in through.Meta.model_fields.values()):
+    if any(field.is_relation for field in through.ormar_config.model_fields.values()):
         raise ModelDefinitionError(
             f"Through Models cannot have explicit relations "
             f"defined. Remove the relations from Model "
@@ -46,7 +44,7 @@ def forbid_through_relations(through: Type["Model"]) -> None:
 
 def populate_m2m_params_based_on_to_model(
     to: Type["Model"], nullable: bool
-) -> Tuple[Any, Any]:
+) -> Tuple[Any, Any, Any]:
     """
     Based on target to model to which relation leads to populates the type of the
     pydantic field to use and type of the target column field.
@@ -58,14 +56,22 @@ def populate_m2m_params_based_on_to_model(
     :return: Tuple[List, Any]
     :rtype: tuple with target pydantic type and target col type
     """
-    to_field = to.Meta.model_fields[to.Meta.pkname]
+    to_field = to.ormar_config.model_fields[to.ormar_config.pkname]
+    pk_only_model = create_dummy_model(to, to_field)
+    base_type = Union[  # type: ignore
+        to_field.__type__,  # type: ignore
+        to,  # type: ignore
+        pk_only_model,  # type: ignore
+        List[to],  # type: ignore
+        List[pk_only_model],  # type: ignore
+    ]
     __type__ = (
-        Union[to_field.__type__, to, List[to]]  # type: ignore
+        base_type  # type: ignore
         if not nullable
-        else Optional[Union[to_field.__type__, to, List[to]]]  # type: ignore
+        else Optional[base_type]  # type: ignore
     )
     column_type = to_field.column_type
-    return __type__, column_type
+    return __type__, column_type, pk_only_model
 
 
 @overload
@@ -79,10 +85,10 @@ def ManyToMany(to: ForwardRef, **kwargs: Any) -> "RelationProxy":  # pragma: no
 
 
 def ManyToMany(  # type: ignore
-    to: "ToType",
-    through: Optional["ToType"] = None,
+    to: Union[Type["T"], "ForwardRef"],
+    through: Optional[Union[Type["T"], "ForwardRef"]] = None,
     *,
-    name: str = None,
+    name: Optional[str] = None,
     unique: bool = False,
     virtual: bool = False,
     **kwargs: Any,
@@ -129,7 +135,7 @@ def ManyToMany(  # type: ignore
         forbid_through_relations(cast(Type["Model"], through))
 
     validate_not_allowed_fields(kwargs)
-
+    pk_only_model = None
     if to.__class__ == ForwardRef:
         __type__ = (
             Union[to, List[to]]  # type: ignore
@@ -138,12 +144,13 @@ def ManyToMany(  # type: ignore
         )
         column_type = None
     else:
-        __type__, column_type = populate_m2m_params_based_on_to_model(
+        __type__, column_type, pk_only_model = populate_m2m_params_based_on_to_model(
             to=to, nullable=nullable  # type: ignore
         )
     namespace = dict(
         __type__=__type__,
         to=to,
+        to_pk_only=pk_only_model,
         through=through,
         alias=name,
         name=name,
@@ -154,7 +161,6 @@ def ManyToMany(  # type: ignore
         virtual=virtual,
         primary_key=False,
         index=False,
-        pydantic_only=False,
         default=None,
         server_default=None,
         owner=owner,
@@ -173,7 +179,11 @@ def ManyToMany(  # type: ignore
     return Field(**namespace)
 
 
-class ManyToManyField(ForeignKeyField, ormar.QuerySetProtocol, ormar.RelationProtocol):
+class ManyToManyField(  # type: ignore
+    ForeignKeyField,
+    ormar.QuerySetProtocol,
+    ormar.RelationProtocol,
+):
     """
     Actual class returned from ManyToMany function call and stored in model_fields.
     """
@@ -194,7 +204,7 @@ class ManyToManyField(ForeignKeyField, ormar.QuerySetProtocol, ormar.RelationPro
         :rtype: str
         """
         return (
-            self.through.Meta.model_fields[
+            self.through.ormar_config.model_fields[
                 self.default_source_field_name()
             ].related_name
             or self.name
@@ -222,18 +232,19 @@ class ManyToManyField(ForeignKeyField, ormar.QuerySetProtocol, ormar.RelationPro
         :rtype: None
         """
         if self.to.__class__ == ForwardRef:
-            self.to = evaluate_forwardref(
-                self.to, globalns, localns or None  # type: ignore
-            )
-
-            (self.__type__, self.column_type) = populate_m2m_params_based_on_to_model(
+            self._evaluate_forward_ref(globalns, localns)
+            (
+                self.__type__,
+                self.column_type,
+                pk_only_model,
+            ) = populate_m2m_params_based_on_to_model(
                 to=self.to, nullable=self.nullable
             )
+            self.to_pk_only = pk_only_model
 
         if self.through.__class__ == ForwardRef:
-            self.through = evaluate_forwardref(
-                self.through, globalns, localns or None  # type: ignore
-            )
+            self._evaluate_forward_ref(globalns, localns, is_through=True)
+
             forbid_through_relations(self.through)
 
     def get_relation_name(self) -> str:
@@ -265,15 +276,22 @@ class ManyToManyField(ForeignKeyField, ormar.QuerySetProtocol, ormar.RelationPro
         to_name = self.to.get_name(lower=False)
         class_name = f"{owner_name}{to_name}"
         table_name = f"{owner_name.lower()}s_{to_name.lower()}s"
-        new_meta_namespace = {
-            "tablename": table_name,
-            "database": self.owner.Meta.database,
-            "metadata": self.owner.Meta.metadata,
+        base_namespace = {
+            "__module__": self.owner.__module__,
+            "__qualname__": f"{self.owner.__qualname__}.{class_name}",
         }
-        new_meta = type("Meta", (), new_meta_namespace)
+        new_config = ormar.models.ormar_config.OrmarConfig(
+            tablename=table_name,
+            database=self.owner.ormar_config.database,
+            metadata=self.owner.ormar_config.metadata,
+        )
         through_model = type(
             class_name,
             (ormar.Model,),
-            {"Meta": new_meta, "id": ormar.Integer(name="id", primary_key=True)},
+            {
+                **base_namespace,
+                "ormar_config": new_config,
+                "id": ormar.Integer(name="id", primary_key=True),
+            },
         )
         self.through = cast(Type["Model"], through_model)
diff --git a/ormar/fields/model_fields.py b/ormar/fields/model_fields.py
index f2f4cfc..e2550bb 100644
--- a/ormar/fields/model_fields.py
+++ b/ormar/fields/model_fields.py
@@ -1,8 +1,9 @@
 import datetime
 import decimal
 import uuid
-from enum import Enum as E, EnumMeta
-from typing import Any, Optional, Set, TYPE_CHECKING, Type, TypeVar, Union, overload
+from enum import Enum as E
+from enum import EnumMeta
+from typing import TYPE_CHECKING, Any, Optional, Type, TypeVar, Union, overload
 
 import pydantic
 import sqlalchemy
@@ -23,7 +24,6 @@ def is_field_nullable(
     nullable: Optional[bool],
     default: Any,
     server_default: Any,
-    pydantic_only: Optional[bool],
 ) -> bool:
     """
     Checks if the given field should be nullable/ optional based on parameters given.
@@ -34,17 +34,11 @@ def is_field_nullable(
     :type default: Any
     :param server_default: function to be called as default by sql server
     :type server_default: Any
-    :param pydantic_only: flag if fields should not be included in the sql table
-    :type pydantic_only: Optional[bool]
     :return: result of the check
     :rtype: bool
     """
     if nullable is None:
-        return (
-            default is not None
-            or server_default is not None
-            or (pydantic_only is not None and pydantic_only)
-        )
+        return default is not None or server_default is not None
     return nullable
 
 
@@ -62,49 +56,6 @@ def is_auto_primary_key(primary_key: bool, autoincrement: bool) -> bool:
     return primary_key and autoincrement
 
 
-def convert_choices_if_needed(
-    field_type: "Type",
-    choices: Set,
-    nullable: bool,
-    scale: int = None,
-    represent_as_str: bool = False,
-) -> Set:
-    """
-    Converts dates to isoformat as fastapi can check this condition in routes
-    and the fields are not yet parsed.
-    Converts enums to list of it's values.
-    Converts uuids to strings.
-    Converts decimal to float with given scale.
-
-    :param field_type: type o the field
-    :type field_type: Type
-    :param choices: set of choices
-    :type choices: Set
-    :param scale: scale for decimals
-    :type scale: int
-    :param nullable: flag if field_nullable
-    :type nullable: bool
-    :param represent_as_str: flag for bytes fields
-    :type represent_as_str: bool
-    :param scale: scale for decimals
-    :type scale: int
-    :return: value, choices list
-    :rtype: Tuple[Any, Set]
-    """
-    choices = {o.value if isinstance(o, E) else o for o in choices}
-    encoder = ormar.ENCODERS_MAP.get(field_type, lambda x: x)
-    if field_type == decimal.Decimal:
-        precision = scale
-        choices = {encoder(o, precision) for o in choices}
-    elif field_type == bytes:
-        choices = {encoder(o, represent_as_str) for o in choices}
-    elif encoder:
-        choices = {encoder(o) for o in choices}
-    if nullable:
-        choices.add(None)
-    return choices
-
-
 class ModelFieldFactory:
     """
     Default field factory that construct Field classes and populated their values.
@@ -115,13 +66,20 @@ class ModelFieldFactory:
     _sample: Any = None
 
     def __new__(cls, *args: Any, **kwargs: Any) -> BaseField:  # type: ignore
+        if "choices" in kwargs:
+            raise ModelDefinitionError(
+                "The choices parameter was removed: use an ormar.Enum field instead."
+            )
+        if "pydantic_only" in kwargs:
+            raise ModelDefinitionError(
+                "The pydantic_only parameter was removed: declare a plain pydantic field instead."
+            )
         cls.validate(**kwargs)
 
         default = kwargs.pop("default", None)
         server_default = kwargs.pop("server_default", None)
         nullable = kwargs.pop("nullable", None)
         sql_nullable = kwargs.pop("sql_nullable", None)
-        pydantic_only = kwargs.pop("pydantic_only", False)
 
         primary_key = kwargs.pop("primary_key", False)
         autoincrement = kwargs.pop("autoincrement", False)
@@ -133,7 +91,7 @@ class ModelFieldFactory:
         overwrite_pydantic_type = kwargs.pop("overwrite_pydantic_type", None)
 
         nullable = is_field_nullable(
-            nullable, default, server_default, pydantic_only
+            nullable, default, server_default
         ) or is_auto_primary_key(primary_key, autoincrement)
         sql_nullable = (
             False
@@ -141,23 +99,16 @@ class ModelFieldFactory:
             else (nullable if sql_nullable is None else sql_nullable)
         )
 
-        choices = set(kwargs.pop("choices", []))
-        if choices:
-            choices = convert_choices_if_needed(
-                field_type=cls._type,
-                choices=choices,
-                nullable=nullable,
-                scale=kwargs.get("scale", None),
-                represent_as_str=kwargs.get("represent_as_base64_str", False),
-            )
         enum_class = kwargs.pop("enum_class", None)
         field_type = cls._type if enum_class is None else enum_class
 
         namespace = dict(
             __type__=field_type,
-            __pydantic_type__=overwrite_pydantic_type
-            if overwrite_pydantic_type is not None
-            else field_type,
+            __pydantic_type__=(
+                overwrite_pydantic_type
+                if overwrite_pydantic_type is not None
+                else field_type
+            ),
             __sample__=cls._sample,
             alias=kwargs.pop("name", None),
             name=None,
@@ -165,15 +116,14 @@ class ModelFieldFactory:
             default=default,
             server_default=server_default,
             nullable=nullable,
+            annotation=field_type,
             sql_nullable=sql_nullable,
             index=kwargs.pop("index", False),
             unique=kwargs.pop("unique", False),
-            pydantic_only=pydantic_only,
             autoincrement=autoincrement,
             column_type=cls.get_column_type(
                 **kwargs, sql_nullable=sql_nullable, enum_class=enum_class
             ),
-            choices=choices,
             encrypt_secret=encrypt_secret,
             encrypt_backend=encrypt_backend,
             encrypt_custom_backend=encrypt_custom_backend,
@@ -216,8 +166,8 @@ class String(ModelFieldFactory, str):
         cls,
         *,
         max_length: int,
-        min_length: int = None,
-        regex: str = None,
+        min_length: Optional[int] = None,
+        regex: Optional[str] = None,
         **kwargs: Any
     ) -> BaseField:  # type: ignore
         kwargs = {
@@ -268,9 +218,9 @@ class Integer(ModelFieldFactory, int):
     def __new__(  # type: ignore
         cls,
         *,
-        minimum: int = None,
-        maximum: int = None,
-        multiple_of: int = None,
+        minimum: Optional[int] = None,
+        maximum: Optional[int] = None,
+        multiple_of: Optional[int] = None,
         **kwargs: Any
     ) -> BaseField:
         autoincrement = kwargs.pop("autoincrement", None)
@@ -349,9 +299,9 @@ class Float(ModelFieldFactory, float):
     def __new__(  # type: ignore
         cls,
         *,
-        minimum: float = None,
-        maximum: float = None,
-        multiple_of: int = None,
+        minimum: Optional[float] = None,
+        maximum: Optional[float] = None,
+        multiple_of: Optional[int] = None,
         **kwargs: Any
     ) -> BaseField:
         kwargs = {
@@ -528,20 +478,17 @@ if TYPE_CHECKING:  # pragma: nocover # noqa: C901
     @overload
     def LargeBinary(  # type: ignore
         max_length: int, *, represent_as_base64_str: Literal[True], **kwargs: Any
-    ) -> str:
-        ...
+    ) -> str: ...
 
     @overload
     def LargeBinary(  # type: ignore
         max_length: int, *, represent_as_base64_str: Literal[False], **kwargs: Any
-    ) -> bytes:
-        ...
+    ) -> bytes: ...
 
     @overload
     def LargeBinary(
         max_length: int, represent_as_base64_str: Literal[False] = ..., **kwargs: Any
-    ) -> bytes:
-        ...
+    ) -> bytes: ...
 
     def LargeBinary(
         max_length: int, represent_as_base64_str: bool = False, **kwargs: Any
@@ -614,9 +561,9 @@ class BigInteger(Integer, int):
     def __new__(  # type: ignore
         cls,
         *,
-        minimum: int = None,
-        maximum: int = None,
-        multiple_of: int = None,
+        minimum: Optional[int] = None,
+        maximum: Optional[int] = None,
+        multiple_of: Optional[int] = None,
         **kwargs: Any
     ) -> BaseField:
         autoincrement = kwargs.pop("autoincrement", None)
@@ -662,9 +609,9 @@ class SmallInteger(Integer, int):
     def __new__(  # type: ignore
         cls,
         *,
-        minimum: int = None,
-        maximum: int = None,
-        multiple_of: int = None,
+        minimum: Optional[int] = None,
+        maximum: Optional[int] = None,
+        multiple_of: Optional[int] = None,
         **kwargs: Any
     ) -> BaseField:
         autoincrement = kwargs.pop("autoincrement", None)
@@ -710,13 +657,13 @@ class Decimal(ModelFieldFactory, decimal.Decimal):
     def __new__(  # type: ignore # noqa CFQ002
         cls,
         *,
-        minimum: float = None,
-        maximum: float = None,
-        multiple_of: int = None,
-        precision: int = None,
-        scale: int = None,
-        max_digits: int = None,
-        decimal_places: int = None,
+        minimum: Optional[float] = None,
+        maximum: Optional[float] = None,
+        multiple_of: Optional[int] = None,
+        precision: Optional[int] = None,
+        scale: Optional[int] = None,
+        max_digits: Optional[int] = None,
+        decimal_places: Optional[int] = None,
         **kwargs: Any
     ) -> BaseField:
         kwargs = {
@@ -810,7 +757,6 @@ class UUID(ModelFieldFactory, uuid.UUID):
 
 
 if TYPE_CHECKING:  # pragma: nocover
-
     T = TypeVar("T", bound=E)
 
     def Enum(enum_class: Type[T], **kwargs: Any) -> T:
@@ -829,7 +775,6 @@ else:
         def __new__(  # type: ignore # noqa CFQ002
             cls, *, enum_class: Type[E], **kwargs: Any
         ) -> BaseField:
-
             kwargs = {
                 **kwargs,
                 **{
diff --git a/ormar/fields/parsers.py b/ormar/fields/parsers.py
index c3d85fe..9b73304 100644
--- a/ormar/fields/parsers.py
+++ b/ormar/fields/parsers.py
@@ -5,7 +5,7 @@ import uuid
 from typing import Any, Callable, Dict, Optional, Union
 
 import pydantic
-from pydantic.datetime_parse import parse_date, parse_datetime, parse_time
+from pydantic_core import SchemaValidator, core_schema
 
 try:
     import orjson as json
@@ -21,17 +21,23 @@ def encode_bool(value: bool) -> str:
     return "true" if value else "false"
 
 
-def encode_decimal(value: decimal.Decimal, precision: int = None) -> float:
-    if precision:
-        return (
-            round(float(value), precision)
-            if isinstance(value, decimal.Decimal)
-            else value
+def encode_decimal(value: decimal.Decimal, precision: Optional[int] = None) -> float:
+    return (
+        round(float(value), precision) if isinstance(value, decimal.Decimal) else value
+    )
+
+
+def encode_bytes(value: Union[str, bytes], represent_as_string: bool = False) -> str:
+    if represent_as_string:
+        value = (
+            value if isinstance(value, str) else base64.b64encode(value).decode("utf-8")
         )
-    return float(value)
+    else:
+        value = value if isinstance(value, str) else value.decode("utf-8")
+    return value
 
 
-def encode_bytes(value: Union[str, bytes], represent_as_string: bool = False) -> bytes:
+def decode_bytes(value: str, represent_as_string: bool = False) -> bytes:
     if represent_as_string:
         return value if isinstance(value, bytes) else base64.b64decode(value)
     return value if isinstance(value, bytes) else value.encode("utf-8")
@@ -47,10 +53,10 @@ def encode_json(value: Any) -> Optional[str]:
 
 def re_dump_value(value: str) -> Union[str, bytes]:
     """
-    Rw-dumps choices due to different string representation in orjson and json
+    Re-dumps value due to different string representation in orjson and json
     :param value: string to re-dump
     :type value: str
-    :return: re-dumped choices
+    :return: re-dumped value
     :rtype: List[str]
     """
     try:
@@ -72,11 +78,20 @@ ENCODERS_MAP: Dict[type, Callable] = {
 
 SQL_ENCODERS_MAP: Dict[type, Callable] = {bool: encode_bool, **ENCODERS_MAP}
 
-DECODERS_MAP = {
+ADDITIONAL_PARAMETERS_MAP: Dict[type, str] = {
+    bytes: "represent_as_base64_str",
+    decimal.Decimal: "decimal_places",
+}
+
+
+DECODERS_MAP: Dict[type, Callable] = {
     bool: parse_bool,
-    datetime.datetime: parse_datetime,
-    datetime.date: parse_date,
-    datetime.time: parse_time,
+    datetime.datetime: SchemaValidator(core_schema.datetime_schema()).validate_python,
+    datetime.date: SchemaValidator(core_schema.date_schema()).validate_python,
+    datetime.time: SchemaValidator(core_schema.time_schema()).validate_python,
     pydantic.Json: json.loads,
-    decimal.Decimal: decimal.Decimal,
+    decimal.Decimal: lambda x, precision: decimal.Decimal(
+        x, context=decimal.Context(prec=precision)
+    ),
+    bytes: decode_bytes,
 }
diff --git a/ormar/fields/referential_actions.py b/ormar/fields/referential_actions.py
index cde15ad..06e5cf5 100644
--- a/ormar/fields/referential_actions.py
+++ b/ormar/fields/referential_actions.py
@@ -2,7 +2,6 @@
 Gathers all referential actions by ormar.
 """
 
-
 from enum import Enum
 
 
diff --git a/ormar/fields/sqlalchemy_encrypted.py b/ormar/fields/sqlalchemy_encrypted.py
index 88dc0af..1ad13f9 100644
--- a/ormar/fields/sqlalchemy_encrypted.py
+++ b/ormar/fields/sqlalchemy_encrypted.py
@@ -2,14 +2,14 @@
 import abc
 import base64
 from enum import Enum
-from typing import Any, Callable, Optional, TYPE_CHECKING, Type, Union
+from typing import TYPE_CHECKING, Any, Callable, Dict, Optional, Tuple, Type, Union
 
 import sqlalchemy.types as types
-from pydantic.utils import lenient_issubclass
 from sqlalchemy.engine import Dialect
 
 import ormar  # noqa: I100, I202
 from ormar import ModelDefinitionError  # noqa: I202, I100
+from ormar.fields.parsers import ADDITIONAL_PARAMETERS_MAP
 
 cryptography = None
 try:  # pragma: nocover
@@ -119,7 +119,7 @@ class EncryptedString(types.TypeDecorator):
         self,
         encrypt_secret: Union[str, Callable],
         encrypt_backend: EncryptBackends = EncryptBackends.FERNET,
-        encrypt_custom_backend: Type[EncryptBackend] = None,
+        encrypt_custom_backend: Optional[Type[EncryptBackend]] = None,
         **kwargs: Any,
     ) -> None:
         _field_type = kwargs.pop("_field_type")
@@ -129,7 +129,11 @@ class EncryptedString(types.TypeDecorator):
                 "In order to encrypt a column 'cryptography' is required!"
             )
         backend = BACKENDS_MAP.get(encrypt_backend, encrypt_custom_backend)
-        if not backend or not lenient_issubclass(backend, EncryptBackend):
+        if (
+            not backend
+            or not isinstance(backend, type)
+            or not issubclass(backend, EncryptBackend)
+        ):
             raise ModelDefinitionError("Wrong or no encrypt backend provided!")
 
         self.backend: EncryptBackend = backend()
@@ -160,9 +164,14 @@ class EncryptedString(types.TypeDecorator):
         try:
             value = self._underlying_type.process_bind_param(value, dialect)
         except AttributeError:
-            encoder = ormar.SQL_ENCODERS_MAP.get(self.type_, None)
-            if encoder:
-                value = encoder(value)  # type: ignore
+            encoder, additional_parameter = self._get_coder_type_and_params(
+                coders=ormar.SQL_ENCODERS_MAP
+            )
+            if encoder is not None:
+                params = [value] + (
+                    [additional_parameter] if additional_parameter else []
+                )
+                value = encoder(*params)
 
         encrypted_value = self.backend.encrypt(value)
         return encrypted_value
@@ -175,8 +184,24 @@ class EncryptedString(types.TypeDecorator):
         try:
             return self._underlying_type.process_result_value(decrypted_value, dialect)
         except AttributeError:
-            decoder = ormar.DECODERS_MAP.get(self.type_, None)
-            if decoder:
-                return decoder(decrypted_value)  # type: ignore
+            decoder, additional_parameter = self._get_coder_type_and_params(
+                coders=ormar.DECODERS_MAP
+            )
+            if decoder is not None:
+                params = [decrypted_value] + (
+                    [additional_parameter] if additional_parameter else []
+                )
+                return decoder(*params)  # type: ignore
 
             return self._field_type.__type__(decrypted_value)  # type: ignore
+
+    def _get_coder_type_and_params(
+        self, coders: Dict[type, Callable]
+    ) -> Tuple[Optional[Callable], Optional[str]]:
+        coder = coders.get(self.type_, None)
+        additional_parameter: Optional[str] = None
+        if self.type_ in ADDITIONAL_PARAMETERS_MAP:
+            additional_parameter = getattr(
+                self._field_type, ADDITIONAL_PARAMETERS_MAP[self.type_]
+            )
+        return coder, additional_parameter
diff --git a/ormar/fields/through_field.py b/ormar/fields/through_field.py
index a469ab3..6165816 100644
--- a/ormar/fields/through_field.py
+++ b/ormar/fields/through_field.py
@@ -1,13 +1,14 @@
 import sys
-from typing import Any, TYPE_CHECKING, Type, Union
+from typing import TYPE_CHECKING, Any, Optional, Type, Union
 
 from ormar.fields.base import BaseField
 from ormar.fields.foreign_key import ForeignKeyField
 
 if TYPE_CHECKING:  # pragma no cover
-    from ormar import Model
     from pydantic.typing import ForwardRef
 
+    from ormar import Model
+
     if sys.version_info < (3, 7):
         ToType = Type[Model]
     else:
@@ -15,7 +16,11 @@ if TYPE_CHECKING:  # pragma no cover
 
 
 def Through(  # noqa CFQ002
-    to: "ToType", *, name: str = None, related_name: str = None, **kwargs: Any
+    to: "ToType",
+    *,
+    name: Optional[str] = None,
+    related_name: Optional[str] = None,
+    **kwargs: Any
 ) -> Any:
     """
     Despite a name it's a function that returns constructed ThroughField.
@@ -50,7 +55,6 @@ def Through(  # noqa CFQ002
         column_type=None,
         primary_key=False,
         index=False,
-        pydantic_only=False,
         default=None,
         server_default=None,
         is_relation=True,
diff --git a/ormar/models/__init__.py b/ormar/models/__init__.py
index 1bac952..fa7bf84 100644
--- a/ormar/models/__init__.py
+++ b/ormar/models/__init__.py
@@ -9,5 +9,14 @@ from ormar.models.model_row import ModelRow  # noqa I100
 from ormar.models.model import Model, T  # noqa I100
 from ormar.models.excludable import ExcludableItems  # noqa I100
 from ormar.models.utils import Extra  # noqa I100
+from ormar.models.ormar_config import OrmarConfig  # noqa I100
 
-__all__ = ["NewBaseModel", "Model", "ModelRow", "ExcludableItems", "T", "Extra"]
+__all__ = [
+    "NewBaseModel",
+    "Model",
+    "ModelRow",
+    "ExcludableItems",
+    "T",
+    "Extra",
+    "OrmarConfig",
+]
diff --git a/ormar/models/descriptors/__init__.py b/ormar/models/descriptors/__init__.py
index 459e48d..58e29e9 100644
--- a/ormar/models/descriptors/__init__.py
+++ b/ormar/models/descriptors/__init__.py
@@ -2,7 +2,6 @@ from ormar.models.descriptors.descriptors import (
     BytesDescriptor,
     JsonDescriptor,
     PkDescriptor,
-    PropertyDescriptor,
     PydanticDescriptor,
     RelationDescriptor,
 )
@@ -10,7 +9,6 @@ from ormar.models.descriptors.descriptors import (
 __all__ = [
     "PydanticDescriptor",
     "RelationDescriptor",
-    "PropertyDescriptor",
     "PkDescriptor",
     "JsonDescriptor",
     "BytesDescriptor",
diff --git a/ormar/models/descriptors/descriptors.py b/ormar/models/descriptors/descriptors.py
index 35f4194..40e96d7 100644
--- a/ormar/models/descriptors/descriptors.py
+++ b/ormar/models/descriptors/descriptors.py
@@ -1,7 +1,7 @@
 import base64
-from typing import Any, TYPE_CHECKING, Type
+from typing import TYPE_CHECKING, Any, Type
 
-from ormar.fields.parsers import encode_json
+from ormar.fields.parsers import decode_bytes, encode_json
 
 if TYPE_CHECKING:  # pragma: no cover
     from ormar import Model
@@ -53,7 +53,7 @@ class BytesDescriptor:
 
     def __get__(self, instance: "Model", owner: Type["Model"]) -> Any:
         value = instance.__dict__.get(self.name, None)
-        field = instance.Meta.model_fields[self.name]
+        field = instance.ormar_config.model_fields[self.name]
         if (
             value is not None
             and field.represent_as_base64_str
@@ -63,12 +63,11 @@ class BytesDescriptor:
         return value
 
     def __set__(self, instance: "Model", value: Any) -> None:
-        field = instance.Meta.model_fields[self.name]
+        field = instance.ormar_config.model_fields[self.name]
         if isinstance(value, str):
-            if field.represent_as_base64_str:
-                value = base64.b64decode(value)
-            else:
-                value = value.encode("utf-8")
+            value = decode_bytes(
+                value=value, represent_as_string=field.represent_as_base64_str
+            )
         instance._internal_set(self.name, value)
         instance.set_save_status(False)
 
@@ -107,36 +106,9 @@ class RelationDescriptor:
         return None  # pragma no cover
 
     def __set__(self, instance: "Model", value: Any) -> None:
-        model = instance.Meta.model_fields[self.name].expand_relationship(
+        instance.ormar_config.model_fields[self.name].expand_relationship(
             value=value, child=instance
         )
-        if isinstance(instance.__dict__.get(self.name), list):
-            # virtual foreign key or many to many
-            # TODO: Fix double items in dict, no effect on real action just ugly repr
-            instance.__dict__[self.name].append(model)
-        else:
-            # foreign key relation
-            instance.__dict__[self.name] = model
-            instance.set_save_status(False)
-
-
-class PropertyDescriptor:
-    """
-    Property descriptor handles methods decorated with @property_field decorator.
-    They are read only.
-    """
 
-    def __init__(self, name: str, function: Any) -> None:
-        self.name = name
-        self.function = function
-
-    def __get__(self, instance: "Model", owner: Type["Model"]) -> Any:
-        if instance is None:
-            return self
-        if instance is not None and self.function is not None:
-            bound = self.function.__get__(instance, instance.__class__)
-            return bound() if callable(bound) else bound
-
-    def __set__(self, instance: "Model", value: Any) -> None:  # pragma: no cover
-        # kept here so it's a data-descriptor and precedes __dict__ lookup
-        pass
+        if not isinstance(instance.__dict__.get(self.name), list):
+            instance.set_save_status(False)
diff --git a/ormar/models/excludable.py b/ormar/models/excludable.py
index 59125c5..2759ad0 100644
--- a/ormar/models/excludable.py
+++ b/ormar/models/excludable.py
@@ -1,5 +1,5 @@
 from dataclasses import dataclass, field
-from typing import Dict, List, Set, TYPE_CHECKING, Tuple, Type, Union
+from typing import TYPE_CHECKING, Dict, List, Optional, Set, Tuple, Type, Union
 
 from ormar.queryset.utils import get_relationship_alias_model_and_str
 
@@ -186,7 +186,7 @@ class ExcludableItems:
         source_model: Type["Model"],
         model_cls: Type["Model"],
         is_exclude: bool,
-        related_items: List = None,
+        related_items: Optional[List] = None,
         alias: str = "",
     ) -> None:
         """
diff --git a/ormar/models/helpers/__init__.py b/ormar/models/helpers/__init__.py
index 0d9e6ce..5d4c1de 100644
--- a/ormar/models/helpers/__init__.py
+++ b/ormar/models/helpers/__init__.py
@@ -1,43 +1,41 @@
 from ormar.models.helpers.models import (
-    check_required_meta_parameters,
+    check_required_config_parameters,
+    config_field_not_set,
     extract_annotations_and_default_vals,
-    meta_field_not_set,
     populate_default_options_values,
 )
 from ormar.models.helpers.pydantic import (
     get_potential_fields,
     get_pydantic_base_orm_config,
-    get_pydantic_field,
     merge_or_generate_pydantic_config,
     remove_excluded_parent_fields,
 )
 from ormar.models.helpers.relations import (
     alias_manager,
+    expand_reverse_relationships,
     register_relation_in_alias_manager,
 )
-from ormar.models.helpers.relations import expand_reverse_relationships
 from ormar.models.helpers.sqlalchemy import (
-    populate_meta_sqlalchemy_table_if_required,
-    populate_meta_tablename_columns_and_pk,
+    populate_config_sqlalchemy_table_if_required,
+    populate_config_tablename_columns_and_pk,
     sqlalchemy_columns_from_model_fields,
 )
-from ormar.models.helpers.validation import populate_choices_validators
+from ormar.models.helpers.validation import modify_schema_example
 
 __all__ = [
     "expand_reverse_relationships",
     "extract_annotations_and_default_vals",
-    "populate_meta_tablename_columns_and_pk",
-    "populate_meta_sqlalchemy_table_if_required",
+    "populate_config_tablename_columns_and_pk",
+    "populate_config_sqlalchemy_table_if_required",
     "populate_default_options_values",
     "alias_manager",
     "register_relation_in_alias_manager",
-    "get_pydantic_field",
     "get_potential_fields",
     "get_pydantic_base_orm_config",
     "merge_or_generate_pydantic_config",
-    "check_required_meta_parameters",
+    "check_required_config_parameters",
     "sqlalchemy_columns_from_model_fields",
-    "populate_choices_validators",
-    "meta_field_not_set",
+    "config_field_not_set",
     "remove_excluded_parent_fields",
+    "modify_schema_example",
 ]
diff --git a/ormar/models/helpers/models.py b/ormar/models/helpers/models.py
index 5bc0a0f..e05ed16 100644
--- a/ormar/models/helpers/models.py
+++ b/ormar/models/helpers/models.py
@@ -1,12 +1,11 @@
 import itertools
 import sqlite3
-from typing import Any, Dict, List, TYPE_CHECKING, Tuple, Type
+from typing import TYPE_CHECKING, Any, Dict, ForwardRef, List, Tuple, Type
 
 import pydantic
-from pydantic.typing import ForwardRef
+
 import ormar  # noqa: I100
 from ormar.models.helpers.pydantic import populate_pydantic_default_values
-from ormar.models.utils import Extra
 
 if TYPE_CHECKING:  # pragma no cover
     from ormar import Model
@@ -32,7 +31,7 @@ def populate_default_options_values(  # noqa: CCR001
     new_model: Type["Model"], model_fields: Dict
 ) -> None:
     """
-    Sets all optional Meta values to it's defaults
+    Sets all optional OrmarConfig values to its defaults
     and set model_fields that were already previously extracted.
 
     Here should live all options that are not overwritten/set for all models.
@@ -46,38 +45,19 @@ def populate_default_options_values(  # noqa: CCR001
     :param model_fields: dict of model fields
     :type model_fields: Union[Dict[str, type], Dict]
     """
-    defaults = {
-        "queryset_class": ormar.QuerySet,
-        "constraints": [],
-        "model_fields": model_fields,
-        "abstract": False,
-        "extra": Extra.forbid,
-        "orders_by": [],
-        "exclude_parent_fields": [],
-    }
-    for key, value in defaults.items():
-        if not hasattr(new_model.Meta, key):
-            setattr(new_model.Meta, key, value)
-
-    if any(
-        is_field_an_forward_ref(field) for field in new_model.Meta.model_fields.values()
-    ):
-        new_model.Meta.requires_ref_update = True
-    else:
-        new_model.Meta.requires_ref_update = False
+    new_model.ormar_config.model_fields.update(model_fields)
+    if any(is_field_an_forward_ref(field) for field in model_fields.values()):
+        new_model.ormar_config.requires_ref_update = True
 
     new_model._json_fields = {
-        name
-        for name, field in new_model.Meta.model_fields.items()
-        if field.__type__ == pydantic.Json
+        name for name, field in model_fields.items() if field.__type__ == pydantic.Json
     }
     new_model._bytes_fields = {
-        name
-        for name, field in new_model.Meta.model_fields.items()
-        if field.__type__ == bytes
+        name for name, field in model_fields.items() if field.__type__ == bytes
     }
 
     new_model.__relation_map__ = None
+    new_model.__ormar_fields_validators__ = None
 
 
 class Connection(sqlite3.Connection):
@@ -94,7 +74,7 @@ def substitue_backend_pool_for_sqlite(new_model: Type["Model"]) -> None:
     :param new_model: newly declared ormar Model
     :type new_model: Model class
     """
-    backend = new_model.Meta.database._backend
+    backend = new_model.ormar_config.database._backend
     if (
         backend._dialect.name == "sqlite" and "factory" not in backend._options
     ):  # pragma: no cover
@@ -103,7 +83,7 @@ def substitue_backend_pool_for_sqlite(new_model: Type["Model"]) -> None:
         backend._pool = old_pool.__class__(backend._database_url, **backend._options)
 
 
-def check_required_meta_parameters(new_model: Type["Model"]) -> None:
+def check_required_config_parameters(new_model: Type["Model"]) -> None:
     """
     Verifies if ormar.Model has database and metadata set.
 
@@ -112,20 +92,17 @@ def check_required_meta_parameters(new_model: Type["Model"]) -> None:
     :param new_model: newly declared ormar Model
     :type new_model: Model class
     """
-    if not hasattr(new_model.Meta, "database"):
-        if not getattr(new_model.Meta, "abstract", False):
-            raise ormar.ModelDefinitionError(
-                f"{new_model.__name__} does not have database defined."
-            )
-
-    else:
+    if new_model.ormar_config.database is None and not new_model.ormar_config.abstract:
+        raise ormar.ModelDefinitionError(
+            f"{new_model.__name__} does not have database defined."
+        )
+    elif not new_model.ormar_config.abstract:
         substitue_backend_pool_for_sqlite(new_model=new_model)
 
-    if not hasattr(new_model.Meta, "metadata"):
-        if not getattr(new_model.Meta, "abstract", False):
-            raise ormar.ModelDefinitionError(
-                f"{new_model.__name__} does not have metadata defined."
-            )
+    if new_model.ormar_config.metadata is None and not new_model.ormar_config.abstract:
+        raise ormar.ModelDefinitionError(
+            f"{new_model.__name__} does not have metadata defined."
+        )
 
 
 def extract_annotations_and_default_vals(attrs: Dict) -> Tuple[Dict, Dict]:
@@ -176,9 +153,9 @@ def group_related_list(list_: List) -> Dict:
     return dict(sorted(result_dict.items(), key=lambda item: len(item[1])))
 
 
-def meta_field_not_set(model: Type["Model"], field_name: str) -> bool:
+def config_field_not_set(model: Type["Model"], field_name: str) -> bool:
     """
-    Checks if field with given name is already present in model.Meta.
+    Checks if field with given name is already present in model.OrmarConfig.
     Then check if it's set to something truthful
     (in practice meaning not None, as it's non or ormar Field only).
 
@@ -189,4 +166,4 @@ def meta_field_not_set(model: Type["Model"], field_name: str) -> bool:
     :return: result of the check
     :rtype: bool
     """
-    return not hasattr(model.Meta, field_name) or not getattr(model.Meta, field_name)
+    return not getattr(model.ormar_config, field_name)
diff --git a/ormar/models/helpers/pydantic.py b/ormar/models/helpers/pydantic.py
index 7b5fb82..27629b9 100644
--- a/ormar/models/helpers/pydantic.py
+++ b/ormar/models/helpers/pydantic.py
@@ -1,10 +1,9 @@
-import inspect
 from types import MappingProxyType
-from typing import Dict, Optional, TYPE_CHECKING, Tuple, Type, Union
+from typing import TYPE_CHECKING, Dict, Optional, Tuple, Type, Union
 
 import pydantic
-from pydantic.fields import ModelField
-from pydantic.utils import lenient_issubclass
+from pydantic import ConfigDict
+from pydantic.fields import FieldInfo
 
 from ormar.exceptions import ModelDefinitionError  # noqa: I100, I202
 from ormar.fields import BaseField
@@ -30,35 +29,10 @@ def create_pydantic_field(
     :param model_field: relation field from which through model is extracted
     :type model_field: ManyToManyField class
     """
-    model_field.through.__fields__[field_name] = ModelField(
-        name=field_name,
-        type_=model,
-        model_config=model.__config__,
-        required=False,
-        class_validators={},
-    )
-
-
-def get_pydantic_field(field_name: str, model: Type["Model"]) -> "ModelField":
-    """
-    Extracts field type and if it's required from Model model_fields by passed
-    field_name. Returns a pydantic field with type of field_name field type.
-
-    :param field_name: field name to fetch from Model and name of pydantic field
-    :type field_name: str
-    :param model: type of field to register
-    :type model: Model class
-    :return: newly created pydantic field
-    :rtype: pydantic.ModelField
-    """
-    type_ = model.Meta.model_fields[field_name].__type__
-    return ModelField(
-        name=field_name,
-        type_=type_,  # type: ignore
-        model_config=model.__config__,
-        required=not model.Meta.model_fields[field_name].nullable,
-        class_validators={},
+    model_field.through.model_fields[field_name] = FieldInfo.from_annotated_attribute(
+        annotation=Optional[model], default=None  # type: ignore
     )
+    model_field.through.model_rebuild(force=True)
 
 
 def populate_pydantic_default_values(attrs: Dict) -> Tuple[Dict, Dict]:
@@ -107,23 +81,21 @@ def merge_or_generate_pydantic_config(attrs: Dict, name: str) -> None:
 
     :rtype: None
     """
-    DefaultConfig = get_pydantic_base_orm_config()
-    if "Config" in attrs:
-        ProvidedConfig = attrs["Config"]
-        if not inspect.isclass(ProvidedConfig):
+    default_config = get_pydantic_base_orm_config()
+    if "model_config" in attrs:
+        provided_config = attrs["model_config"]
+        if not isinstance(provided_config, dict):
             raise ModelDefinitionError(
-                f"Config provided for class {name} has to be a class."
+                f"Config provided for class {name} has to be a dictionary."
             )
 
-        class Config(ProvidedConfig, DefaultConfig):  # type: ignore
-            pass
-
-        attrs["Config"] = Config
+        config = {**default_config, **provided_config}
+        attrs["model_config"] = config
     else:
-        attrs["Config"] = DefaultConfig
+        attrs["model_config"] = default_config
 
 
-def get_pydantic_base_orm_config() -> Type[pydantic.BaseConfig]:
+def get_pydantic_base_orm_config() -> pydantic.ConfigDict:
     """
     Returns empty pydantic Config with orm_mode set to True.
 
@@ -131,11 +103,7 @@ def get_pydantic_base_orm_config() -> Type[pydantic.BaseConfig]:
     :rtype: pydantic Config
     """
 
-    class Config(pydantic.BaseConfig):
-        orm_mode = True
-        validate_assignment = True
-
-    return Config
+    return ConfigDict(validate_assignment=True, ser_json_bytes="base64")
 
 
 def get_potential_fields(attrs: Union[Dict, MappingProxyType]) -> Dict:
@@ -150,7 +118,10 @@ def get_potential_fields(attrs: Union[Dict, MappingProxyType]) -> Dict:
     return {
         k: v
         for k, v in attrs.items()
-        if (lenient_issubclass(v, BaseField) or isinstance(v, BaseField))
+        if (
+            (isinstance(v, type) and issubclass(v, BaseField))
+            or isinstance(v, BaseField)
+        )
     }
 
 
@@ -161,8 +132,11 @@ def remove_excluded_parent_fields(model: Type["Model"]) -> None:
     :param model:
     :type model: Type["Model"]
     """
-    excludes = {*model.Meta.exclude_parent_fields} - {*model.Meta.model_fields.keys()}
+    excludes = {*model.ormar_config.exclude_parent_fields} - {
+        *model.ormar_config.model_fields.keys()
+    }
     if excludes:
-        model.__fields__ = {
-            k: v for k, v in model.__fields__.items() if k not in excludes
+        model.model_fields = {
+            k: v for k, v in model.model_fields.items() if k not in excludes
         }
+        model.model_rebuild(force=True)
diff --git a/ormar/models/helpers/related_names_validation.py b/ormar/models/helpers/related_names_validation.py
index 56497b2..d086ed0 100644
--- a/ormar/models/helpers/related_names_validation.py
+++ b/ormar/models/helpers/related_names_validation.py
@@ -1,6 +1,5 @@
-from typing import Dict, List, Optional, TYPE_CHECKING, Type
+from typing import TYPE_CHECKING, Dict, ForwardRef, List, Optional, Type
 
-from pydantic.typing import ForwardRef
 import ormar  # noqa: I100
 
 if TYPE_CHECKING:  # pragma no cover
diff --git a/ormar/models/helpers/relations.py b/ormar/models/helpers/relations.py
index c6d1ba4..823efc6 100644
--- a/ormar/models/helpers/relations.py
+++ b/ormar/models/helpers/relations.py
@@ -1,4 +1,13 @@
-from typing import TYPE_CHECKING, Type, cast
+import inspect
+import warnings
+from typing import TYPE_CHECKING, Any, List, Optional, Type, Union, cast
+
+from pydantic import BaseModel, create_model, field_serializer
+from pydantic._internal._decorators import DecoratorInfos
+from pydantic.fields import FieldInfo
+from pydantic_core.core_schema import (
+    SerializerFunctionWrapHandler,
+)
 
 import ormar
 from ormar import ForeignKey, ManyToMany
@@ -9,7 +18,7 @@ from ormar.relations import AliasManager
 
 if TYPE_CHECKING:  # pragma no cover
     from ormar import Model
-    from ormar.fields import ManyToManyField, ForeignKeyField
+    from ormar.fields import ForeignKeyField, ManyToManyField
 
 alias_manager = AliasManager()
 
@@ -82,7 +91,7 @@ def expand_reverse_relationships(model: Type["Model"]) -> None:
     :param model: model on which relation should be checked and registered
     :type model: Model class
     """
-    model_fields = list(model.Meta.model_fields.values())
+    model_fields = list(model.ormar_config.model_fields.values())
     for model_field in model_fields:
         if model_field.is_relation and not model_field.has_unresolved_forward_refs():
             model_field = cast("ForeignKeyField", model_field)
@@ -101,9 +110,9 @@ def register_reverse_model_fields(model_field: "ForeignKeyField") -> None:
     :type model_field: relation Field
     """
     related_name = model_field.get_related_name()
-    # TODO: Reverse relations does not register pydantic fields?
+    related_model_fields = model_field.to.ormar_config.model_fields
     if model_field.is_multi:
-        model_field.to.Meta.model_fields[related_name] = ManyToMany(  # type: ignore
+        related_model_fields[related_name] = ManyToMany(  # type: ignore
             model_field.owner,
             through=model_field.through,
             name=related_name,
@@ -122,7 +131,7 @@ def register_reverse_model_fields(model_field: "ForeignKeyField") -> None:
         register_through_shortcut_fields(model_field=model_field)
         adjust_through_many_to_many_model(model_field=model_field)
     else:
-        model_field.to.Meta.model_fields[related_name] = ForeignKey(  # type: ignore
+        related_model_fields[related_name] = ForeignKey(  # type: ignore
             model_field.owner,
             real_name=related_name,
             virtual=True,
@@ -133,9 +142,97 @@ def register_reverse_model_fields(model_field: "ForeignKeyField") -> None:
             skip_field=model_field.skip_reverse,
         )
     if not model_field.skip_reverse:
+        field_type = related_model_fields[related_name].__type__
+        field_type = replace_models_with_copy(
+            annotation=field_type, source_model_field=model_field.name
+        )
+        if not model_field.is_multi:
+            field_type = Union[field_type, List[field_type], None]  # type: ignore
+        model_field.to.model_fields[related_name] = FieldInfo.from_annotated_attribute(
+            annotation=field_type, default=None
+        )
+        add_field_serializer_for_reverse_relations(
+            to_model=model_field.to, related_name=related_name
+        )
+        model_field.to.model_rebuild(force=True)
         setattr(model_field.to, related_name, RelationDescriptor(name=related_name))
 
 
+def add_field_serializer_for_reverse_relations(
+    to_model: Type["Model"], related_name: str
+) -> None:
+    def serialize(
+        self: "Model", children: List["Model"], handler: SerializerFunctionWrapHandler
+    ) -> Any:
+        """
+        Serialize a list of nodes, handling circular references
+        by excluding the children.
+        """
+        try:
+            with warnings.catch_warnings():
+                warnings.filterwarnings(
+                    "ignore", message="Pydantic serializer warnings"
+                )
+                return handler(children)
+        except ValueError as exc:
+            if not str(exc).startswith("Circular reference"):  # pragma: no cover
+                raise exc
+
+            result = []
+            for child in children:
+                # If there is one circular ref dump all children as pk only
+                result.append({child.ormar_config.pkname: child.pk})
+            return result
+
+    decorator = field_serializer(related_name, mode="wrap", check_fields=False)(
+        serialize
+    )
+    setattr(to_model, f"serialize_{related_name}", decorator)
+    DecoratorInfos.build(to_model)
+
+
+def replace_models_with_copy(
+    annotation: Type, source_model_field: Optional[str] = None
+) -> Any:
+    """
+    Replaces all models in annotation with their copies to avoid circular references.
+
+    :param annotation: annotation to replace models in
+    :type annotation: Type
+    :return: annotation with replaced models
+    :rtype: Type
+    """
+    if inspect.isclass(annotation) and issubclass(annotation, ormar.Model):
+        return create_copy_to_avoid_circular_references(model=annotation)
+    elif hasattr(annotation, "__origin__") and annotation.__origin__ in {list, Union}:
+        if annotation.__origin__ == list:
+            return List[  # type: ignore
+                replace_models_with_copy(
+                    annotation=annotation.__args__[0],
+                    source_model_field=source_model_field,
+                )
+            ]
+        elif annotation.__origin__ == Union:
+            args = annotation.__args__
+            new_args = [
+                replace_models_with_copy(
+                    annotation=arg, source_model_field=source_model_field
+                )
+                for arg in args
+            ]
+            return Union[tuple(new_args)]
+    else:
+        return annotation
+
+
+def create_copy_to_avoid_circular_references(model: Type["Model"]) -> Type["BaseModel"]:
+    new_model = create_model(
+        model.__name__,
+        __base__=model,
+    )
+    return new_model
+
+
 def register_through_shortcut_fields(model_field: "ManyToManyField") -> None:
     """
     Registers m2m relation through shortcut on both ends of the relation.
@@ -147,7 +244,7 @@ def register_through_shortcut_fields(model_field: "ManyToManyField") -> None:
     through_name = through_model.get_name(lower=True)
     related_name = model_field.get_related_name()
 
-    model_field.owner.Meta.model_fields[through_name] = Through(
+    model_field.owner.ormar_config.model_fields[through_name] = Through(
         through_model,
         real_name=through_name,
         virtual=True,
@@ -156,7 +253,7 @@ def register_through_shortcut_fields(model_field: "ManyToManyField") -> None:
         nullable=True,
     )
 
-    model_field.to.Meta.model_fields[through_name] = Through(
+    model_field.to.ormar_config.model_fields[through_name] = Through(
         through_model,
         real_name=through_name,
         virtual=True,
@@ -209,10 +306,13 @@ def verify_related_name_dont_duplicate(
     :return: None
     :rtype: None
     """
-    fk_field = model_field.to.Meta.model_fields.get(related_name)
+    fk_field = model_field.to.ormar_config.model_fields.get(related_name)
     if not fk_field:  # pragma: no cover
         return
-    if fk_field.to != model_field.owner and fk_field.to.Meta != model_field.owner.Meta:
+    if (
+        fk_field.to != model_field.owner
+        and fk_field.to.ormar_config != model_field.owner.ormar_config
+    ):
         raise ormar.ModelDefinitionError(
             f"Relation with related_name "
             f"'{related_name}' "
@@ -237,8 +337,10 @@ def reverse_field_not_already_registered(model_field: "ForeignKeyField") -> bool
     :rtype: bool
     """
     related_name = model_field.get_related_name()
-    check_result = related_name not in model_field.to.Meta.model_fields
-    check_result2 = model_field.owner.get_name() not in model_field.to.Meta.model_fields
+    check_result = related_name not in model_field.to.ormar_config.model_fields
+    check_result2 = (
+        model_field.owner.get_name() not in model_field.to.ormar_config.model_fields
+    )
 
     if not check_result:
         verify_related_name_dont_duplicate(
diff --git a/ormar/models/helpers/sqlalchemy.py b/ormar/models/helpers/sqlalchemy.py
index b0ade1d..1a4fd97 100644
--- a/ormar/models/helpers/sqlalchemy.py
+++ b/ormar/models/helpers/sqlalchemy.py
@@ -1,8 +1,7 @@
 import logging
-from typing import Dict, List, Optional, TYPE_CHECKING, Tuple, Type, Union
+from typing import TYPE_CHECKING, Dict, ForwardRef, List, Optional, Tuple, Type, Union
 
 import sqlalchemy
-from pydantic.typing import ForwardRef
 
 import ormar  # noqa: I100, I202
 from ormar.models.descriptors import RelationDescriptor
@@ -12,8 +11,9 @@ from ormar.models.helpers.related_names_validation import (
 )
 
 if TYPE_CHECKING:  # pragma no cover
-    from ormar import Model, ModelMeta, ManyToManyField, BaseField, ForeignKeyField
+    from ormar import BaseField, ForeignKeyField, ManyToManyField, Model
     from ormar.models import NewBaseModel
+    from ormar.models.ormar_config import OrmarConfig
 
 
 def adjust_through_many_to_many_model(model_field: "ManyToManyField") -> None:
@@ -28,7 +28,7 @@ def adjust_through_many_to_many_model(model_field: "ManyToManyField") -> None:
     """
     parent_name = model_field.default_target_field_name()
     child_name = model_field.default_source_field_name()
-    model_fields = model_field.through.Meta.model_fields
+    model_fields = model_field.through.ormar_config.model_fields
     model_fields[parent_name] = ormar.ForeignKey(  # type: ignore
         model_field.to,
         real_name=parent_name,
@@ -63,7 +63,8 @@ def create_and_append_m2m_fk(
     """
     Registers sqlalchemy Column with sqlalchemy.ForeignKey leading to the model.
 
-    Newly created field is added to m2m relation through model Meta columns and table.
+    Newly created field is added to m2m relation
+    through model OrmarConfig columns and table.
 
     :param field_name: name of the column to create
     :type field_name: str
@@ -72,8 +73,10 @@ def create_and_append_m2m_fk(
     :param model_field: field with ManyToMany relation
     :type model_field: ManyToManyField field
     """
-    pk_alias = model.get_column_alias(model.Meta.pkname)
-    pk_column = next((col for col in model.Meta.columns if col.name == pk_alias), None)
+    pk_alias = model.get_column_alias(model.ormar_config.pkname)
+    pk_column = next(
+        (col for col in model.ormar_config.columns if col.name == pk_alias), None
+    )
     if pk_column is None:  # pragma: no cover
         raise ormar.ModelDefinitionError(
             "ManyToMany relation cannot lead to field without pk"
@@ -82,15 +85,15 @@ def create_and_append_m2m_fk(
         field_name,
         pk_column.type,
         sqlalchemy.schema.ForeignKey(
-            model.Meta.tablename + "." + pk_alias,
+            model.ormar_config.tablename + "." + pk_alias,
             ondelete="CASCADE",
             onupdate="CASCADE",
-            name=f"fk_{model_field.through.Meta.tablename}_{model.Meta.tablename}"
+            name=f"fk_{model_field.through.ormar_config.tablename}_{model.ormar_config.tablename}"
             f"_{field_name}_{pk_alias}",
         ),
     )
-    model_field.through.Meta.columns.append(column)
-    model_field.through.Meta.table.append_column(column)
+    model_field.through.ormar_config.columns.append(column)
+    model_field.through.ormar_config.table.append_column(column)
 
 
 def check_pk_column_validity(
@@ -98,10 +101,9 @@ def check_pk_column_validity(
 ) -> Optional[str]:
     """
     Receives the field marked as primary key and verifies if the pkname
-    was not already set (only one allowed per model) and if field is not marked
-    as pydantic_only as it needs to be a database field.
+    was not already set (only one allowed per model).
 
-    :raises ModelDefintionError: if pkname already set or field is pydantic_only
+    :raises ModelDefintionError: if pkname already set
     :param field_name: name of field
     :type field_name: str
     :param field: ormar.Field
@@ -113,8 +115,6 @@ def check_pk_column_validity(
     """
     if pkname is not None:
         raise ormar.ModelDefinitionError("Only one primary key column is allowed.")
-    if field.pydantic_only:
-        raise ormar.ModelDefinitionError("Primary key column cannot be pydantic only")
     return field_name
 
 
@@ -132,11 +132,7 @@ def sqlalchemy_columns_from_model_fields(
     are leading to the same related model only one can have empty related_name param.
     Also related_names have to be unique.
 
-    Trigger validation of primary_key - only one and required pk can be set,
-    cannot be pydantic_only.
-
-    Append fields to columns if it's not pydantic_only,
-    virtual ForeignKey or ManyToMany field.
+    Trigger validation of primary_key - only one and required pk can be set
 
     Sets `owner` on each model_field as reference to newly created Model.
 
@@ -152,7 +148,7 @@ def sqlalchemy_columns_from_model_fields(
     if len(model_fields.keys()) == 0:
         model_fields["id"] = ormar.Integer(name="id", primary_key=True)
         logging.warning(
-            f"Table {new_model.Meta.tablename} had no fields so auto "
+            f"Table {new_model.ormar_config.tablename} had no fields so auto "
             "Integer primary key named `id` created."
         )
     validate_related_names_in_relations(model_fields, new_model)
@@ -166,11 +162,6 @@ def _process_fields(
     Helper method.
 
     Populates pkname and columns.
-    Trigger validation of primary_key - only one and required pk can be set,
-    cannot be pydantic_only.
-
-    Append fields to columns if it's not pydantic_only,
-    virtual ForeignKey or ManyToMany field.
 
     Sets `owner` on each model_field as reference to newly created Model.
 
@@ -215,17 +206,17 @@ def _is_db_field(field: "BaseField") -> bool:
     :return: result of the check
     :rtype: bool
     """
-    return not field.pydantic_only and not field.virtual and not field.is_multi
+    return not field.virtual and not field.is_multi
 
 
-def populate_meta_tablename_columns_and_pk(
+def populate_config_tablename_columns_and_pk(
     name: str, new_model: Type["Model"]
 ) -> Type["Model"]:
     """
-    Sets Model tablename if it's not already set in Meta.
+    Sets Model tablename if it's not already set in OrmarConfig.
     Default tablename if not present is class name lower + s (i.e. Bed becomes -> beds)
 
-    Checks if Model's Meta have pkname and columns set.
+    Checks if Model's OrmarConfig have pkname and columns set.
     If not calls the sqlalchemy_columns_from_model_fields to populate
     columns from ormar.fields definitions.
 
@@ -236,77 +227,79 @@ def populate_meta_tablename_columns_and_pk(
     :type name: str
     :param new_model: currently constructed Model
     :type new_model: ormar.models.metaclass.ModelMetaclass
-    :return: Model with populated pkname and columns in Meta
+    :return: Model with populated pkname and columns in OrmarConfig
     :rtype: ormar.models.metaclass.ModelMetaclass
     """
     tablename = name.lower() + "s"
-    new_model.Meta.tablename = (
-        new_model.Meta.tablename if hasattr(new_model.Meta, "tablename") else tablename
+    new_model.ormar_config.tablename = (
+        new_model.ormar_config.tablename
+        if new_model.ormar_config.tablename
+        else tablename
     )
     pkname: Optional[str]
 
-    if hasattr(new_model.Meta, "columns"):
-        columns = new_model.Meta.columns
-        pkname = new_model.Meta.pkname
+    if new_model.ormar_config.columns:
+        columns = new_model.ormar_config.columns
+        pkname = new_model.ormar_config.pkname
     else:
         pkname, columns = sqlalchemy_columns_from_model_fields(
-            new_model.Meta.model_fields, new_model
+            new_model.ormar_config.model_fields, new_model
         )
 
     if pkname is None:
         raise ormar.ModelDefinitionError("Table has to have a primary key.")
 
-    new_model.Meta.columns = columns
-    new_model.Meta.pkname = pkname
-    if not new_model.Meta.orders_by:
-        # by default we sort by pk name if other option not provided
-        new_model.Meta.orders_by.append(pkname)
+    new_model.ormar_config.columns = columns
+    new_model.ormar_config.pkname = pkname
+    if not new_model.ormar_config.orders_by:
+        # by default, we sort by pk name if other option not provided
+        new_model.ormar_config.orders_by.append(pkname)
     return new_model
 
 
-def check_for_null_type_columns_from_forward_refs(meta: "ModelMeta") -> bool:
+def check_for_null_type_columns_from_forward_refs(config: "OrmarConfig") -> bool:
     """
     Check is any column is of NUllType() meaning it's empty column from ForwardRef
 
-    :param meta: Meta class of the Model without sqlalchemy table constructed
-    :type meta: Model class Meta
+    :param config: OrmarConfig of the Model without sqlalchemy table constructed
+    :type config: Model class OrmarConfig
     :return: result of the check
     :rtype: bool
     """
     return not any(
-        isinstance(col.type, sqlalchemy.sql.sqltypes.NullType) for col in meta.columns
+        isinstance(col.type, sqlalchemy.sql.sqltypes.NullType) for col in config.columns
     )
 
 
-def populate_meta_sqlalchemy_table_if_required(meta: "ModelMeta") -> None:
+def populate_config_sqlalchemy_table_if_required(config: "OrmarConfig") -> None:
     """
-    Constructs sqlalchemy table out of columns and parameters set on Meta class.
+    Constructs sqlalchemy table out of columns and parameters set on OrmarConfig.
     It populates name, metadata, columns and constraints.
 
-    :param meta: Meta class of the Model without sqlalchemy table constructed
-    :type meta: Model class Meta
+    :param config: OrmarConfig of the Model without sqlalchemy table constructed
+    :type config: Model class OrmarConfig
     """
-    if not hasattr(meta, "table") and check_for_null_type_columns_from_forward_refs(
-        meta
+    if config.table is None and check_for_null_type_columns_from_forward_refs(
+        config=config
     ):
-        set_constraint_names(meta=meta)
+        set_constraint_names(config=config)
         table = sqlalchemy.Table(
-            meta.tablename, meta.metadata, *meta.columns, *meta.constraints
+            config.tablename, config.metadata, *config.columns, *config.constraints
         )
-        meta.table = table
+        config.table = table
 
 
-def set_constraint_names(meta: "ModelMeta") -> None:
+def set_constraint_names(config: "OrmarConfig") -> None:
     """
     Populates the names on IndexColumns and UniqueColumns and CheckColumns constraints.
 
-    :param meta: Meta class of the Model without sqlalchemy table constructed
-    :type meta: Model class Meta
+    :param config: OrmarConfig of the Model without sqlalchemy table constructed
+    :type config: Model class OrmarConfig
     """
-    for constraint in meta.constraints:
+    for constraint in config.constraints:
         if isinstance(constraint, sqlalchemy.UniqueConstraint) and not constraint.name:
             constraint.name = (
-                f"uc_{meta.tablename}_"
+                f"uc_{config.tablename}_"
                 f'{"_".join([str(col) for col in constraint._pending_colargs])}'
             )
         elif (
@@ -314,12 +307,12 @@ def set_constraint_names(meta: "ModelMeta") -> None:
             and constraint.name == "TEMPORARY_NAME"
         ):
             constraint.name = (
-                f"ix_{meta.tablename}_"
+                f"ix_{config.tablename}_"
                 f'{"_".join([col for col in constraint._pending_colargs])}'
             )
         elif isinstance(constraint, sqlalchemy.CheckConstraint) and not constraint.name:
             sql_condition: str = str(constraint.sqltext).replace(" ", "_")
-            constraint.name = f"check_{meta.tablename}_{sql_condition}"
+            constraint.name = f"check_{config.tablename}_{sql_condition}"
 
 
 def update_column_definition(
@@ -335,7 +328,7 @@ def update_column_definition(
     :return: None
     :rtype: None
     """
-    columns = model.Meta.columns
+    columns = model.ormar_config.columns
     for ind, column in enumerate(columns):
         if column.name == field.get_alias():
             new_column = field.get_column(field.get_alias())
diff --git a/ormar/models/helpers/validation.py b/ormar/models/helpers/validation.py
index d25837d..f284ce8 100644
--- a/ormar/models/helpers/validation.py
+++ b/ormar/models/helpers/validation.py
@@ -1,13 +1,13 @@
-import base64
 import decimal
 import numbers
 from typing import (
+    TYPE_CHECKING,
     Any,
     Callable,
     Dict,
     List,
+    Optional,
     Set,
-    TYPE_CHECKING,
     Type,
     Union,
 )
@@ -18,11 +18,8 @@ except ImportError:  # pragma: no cover
     import json  # type: ignore  # noqa: F401
 
 import pydantic
-from pydantic.class_validators import make_generic_validator
-from pydantic.fields import ModelField, SHAPE_LIST
 
-import ormar  # noqa: I100, I202
-from ormar.models.helpers.models import meta_field_not_set
+from ormar.models.helpers.models import config_field_not_set
 from ormar.queryset.utils import translate_list_to_dict
 
 if TYPE_CHECKING:  # pragma no cover
@@ -30,72 +27,9 @@ if TYPE_CHECKING:  # pragma no cover
     from ormar.fields import BaseField
 
 
-def check_if_field_has_choices(field: "BaseField") -> bool:
-    """
-    Checks if given field has choices populated.
-    A if it has one, a validator for this field needs to be attached.
-
-    :param field: ormar field to check
-    :type field: BaseField
-    :return: result of the check
-    :rtype: bool
-    """
-    return hasattr(field, "choices") and bool(field.choices)
-
-
-def convert_value_if_needed(field: "BaseField", value: Any) -> Any:
-    """
-    Converts dates to isoformat as fastapi can check this condition in routes
-    and the fields are not yet parsed.
-    Converts enums to list of it's values.
-    Converts uuids to strings.
-    Converts decimal to float with given scale.
-
-    :param field: ormar field to check with choices
-    :type field: BaseField
-    :param value: current values of the model to verify
-    :type value: Any
-    :return: value, choices list
-    :rtype: Any
-    """
-    encoder = ormar.ENCODERS_MAP.get(field.__type__, lambda x: x)
-    if field.__type__ == decimal.Decimal:
-        precision = field.scale  # type: ignore
-        value = encoder(value, precision)
-    elif field.__type__ == bytes:
-        represent_as_string = field.represent_as_base64_str
-        value = encoder(value, represent_as_string)
-    elif encoder:
-        value = encoder(value)
-    return value
-
-
-def generate_validator(ormar_field: "BaseField") -> Callable:
-    choices = ormar_field.choices
-
-    def validate_choices(cls: type, value: Any, field: "ModelField") -> None:
-        """
-        Validates if given value is in provided choices.
-
-        :raises ValueError: If value is not in choices.
-        :param field:field to validate
-        :type field: BaseField
-        :param value: value of the field
-        :type value: Any
-        """
-        adjusted_value = convert_value_if_needed(field=ormar_field, value=value)
-        if adjusted_value is not ormar.Undefined and adjusted_value not in choices:
-            raise ValueError(
-                f"{field.name}: '{adjusted_value}' "
-                f"not in allowed choices set:"
-                f" {choices}"
-            )
-        return value
-
-    return validate_choices
-
-
-def generate_model_example(model: Type["Model"], relation_map: Dict = None) -> Dict:
+def generate_model_example(
+    model: Type["Model"], relation_map: Optional[Dict] = None
+) -> Dict:
     """
     Generates example to be included in schema in fastapi.
 
@@ -112,11 +46,11 @@ def generate_model_example(model: Type["Model"], relation_map: Dict = None) -> D
         if relation_map is not None
         else translate_list_to_dict(model._iterate_related_models())
     )
-    for name, field in model.Meta.model_fields.items():
+    for name, field in model.ormar_config.model_fields.items():
         populates_sample_fields_values(
             example=example, name=name, field=field, relation_map=relation_map
         )
-    to_exclude = {name for name in model.Meta.model_fields}
+    to_exclude = {name for name in model.ormar_config.model_fields}
     pydantic_repr = generate_pydantic_example(pydantic_model=model, exclude=to_exclude)
     example.update(pydantic_repr)
 
@@ -124,7 +58,10 @@ def generate_model_example(model: Type["Model"], relation_map: Dict = None) -> D
 
 
 def populates_sample_fields_values(
-    example: Dict[str, Any], name: str, field: "BaseField", relation_map: Dict = None
+    example: Dict[str, Any],
+    name: str,
+    field: "BaseField",
+    relation_map: Optional[Dict] = None,
 ) -> None:
     """
     Iterates the field and sets fields to sample values
@@ -168,7 +105,7 @@ def get_nested_model_example(
 
 
 def generate_pydantic_example(
-    pydantic_model: Type[pydantic.BaseModel], exclude: Set = None
+    pydantic_model: Type[pydantic.BaseModel], exclude: Optional[Set] = None
 ) -> Dict:
     """
     Generates dict with example.
@@ -182,14 +119,13 @@ def generate_pydantic_example(
     """
     example: Dict[str, Any] = dict()
     exclude = exclude or set()
-    name_to_check = [name for name in pydantic_model.__fields__ if name not in exclude]
+    name_to_check = [
+        name for name in pydantic_model.model_fields if name not in exclude
+    ]
     for name in name_to_check:
-        field = pydantic_model.__fields__[name]
-        type_ = field.type_
-        if field.shape == SHAPE_LIST:
-            example[name] = [get_pydantic_example_repr(type_)]
-        else:
-            example[name] = get_pydantic_example_repr(type_)
+        field = pydantic_model.model_fields[name]
+        type_ = field.annotation
+        example[name] = get_pydantic_example_repr(type_)
     return example
 
 
@@ -202,6 +138,8 @@ def get_pydantic_example_repr(type_: Any) -> Any:
     :return: representation to include in example
     :rtype: Any
     """
+    if hasattr(type_, "__origin__"):
+        return generate_example_for_nested_types(type_)
     if issubclass(type_, (numbers.Number, decimal.Decimal)):
         return 0
     if issubclass(type_, pydantic.BaseModel):
@@ -209,6 +147,27 @@ def get_pydantic_example_repr(type_: Any) -> Any:
     return "string"
 
 
+def generate_example_for_nested_types(type_: Any) -> Any:
+    """
+    Process nested types like Union[X, Y] or List[X]
+    """
+    if type_.__origin__ == Union:
+        return generate_example_for_union(type_=type_)
+    if type_.__origin__ == list:
+        return [get_pydantic_example_repr(type_.__args__[0])]
+
+
+def generate_example_for_union(type_: Any) -> Any:
+    """
+    Generates a pydantic example for Union[X, Y, ...].
+    Note that Optional can also be set as Union[X, None]
+    """
+    values = tuple(
+        get_pydantic_example_repr(x) for x in type_.__args__ if x is not type(None)
+    )
+    return values[0] if len(values) == 1 else values
+
+
 def overwrite_example_and_description(
     schema: Dict[str, Any], model: Type["Model"]
 ) -> None:
@@ -222,8 +181,6 @@ def overwrite_example_and_description(
     :type model: Type["Model"]
     """
     schema["example"] = generate_model_example(model=model)
-    if "Main base class of ormar Model." in schema.get("description", ""):
-        schema["description"] = f"{model.__name__}"
 
 
 def overwrite_binary_format(schema: Dict[str, Any], model: Type["Model"]) -> None:
@@ -239,42 +196,12 @@ def overwrite_binary_format(schema: Dict[str, Any], model: Type["Model"]) -> Non
     for field_id, prop in schema.get("properties", {}).items():
         if (
             field_id in model._bytes_fields
-            and model.Meta.model_fields[field_id].represent_as_base64_str
+            and model.ormar_config.model_fields[field_id].represent_as_base64_str
         ):
             prop["format"] = "base64"
-            if prop.get("enum"):
-                prop["enum"] = [
-                    base64.b64encode(choice).decode() for choice in prop.get("enum", [])
-                ]
-
-
-def construct_modify_schema_function(fields_with_choices: List) -> Callable:
-    """
-    Modifies the schema to include fields with choices validator.
-    Those fields will be displayed in schema as Enum types with available choices
-    values listed next to them.
-
-    Note that schema extra has to be a function, otherwise it's called to soon
-    before all the relations are expanded.
-
-    :param fields_with_choices: list of fields with choices validation
-    :type fields_with_choices: List
-    :return: callable that will be run by pydantic to modify the schema
-    :rtype: Callable
-    """
-
-    def schema_extra(schema: Dict[str, Any], model: Type["Model"]) -> None:
-        for field_id, prop in schema.get("properties", {}).items():
-            if field_id in fields_with_choices:
-                prop["enum"] = list(model.Meta.model_fields[field_id].choices)
-                prop["description"] = prop.get("description", "") + "An enumeration."
-        overwrite_example_and_description(schema=schema, model=model)
-        overwrite_binary_format(schema=schema, model=model)
-
-    return staticmethod(schema_extra)  # type: ignore
 
 
-def construct_schema_function_without_choices() -> Callable:
+def construct_schema_function() -> Callable:
     """
     Modifies model example and description if needed.
 
@@ -292,28 +219,12 @@ def construct_schema_function_without_choices() -> Callable:
     return staticmethod(schema_extra)  # type: ignore
 
 
-def populate_choices_validators(model: Type["Model"]) -> None:  # noqa CCR001
+def modify_schema_example(model: Type["Model"]) -> None:  # noqa CCR001
     """
-    Checks if Model has any fields with choices set.
-    If yes it adds choices validation into pre root validators.
+    Modifies the schema example in openapi schema.
 
     :param model: newly constructed Model
     :type model: Model class
     """
-    fields_with_choices = []
-    if not meta_field_not_set(model=model, field_name="model_fields"):
-        if not hasattr(model, "_choices_fields"):
-            model._choices_fields = set()
-        for name, field in model.Meta.model_fields.items():
-            if check_if_field_has_choices(field) and name not in model._choices_fields:
-                fields_with_choices.append(name)
-                validator = make_generic_validator(generate_validator(field))
-                model.__fields__[name].validators.append(validator)
-                model._choices_fields.add(name)
-
-        if fields_with_choices:
-            model.Config.schema_extra = construct_modify_schema_function(
-                fields_with_choices=fields_with_choices
-            )
-        else:
-            model.Config.schema_extra = construct_schema_function_without_choices()
+    if not config_field_not_set(model=model, field_name="model_fields"):
+        model.model_config["json_schema_extra"] = construct_schema_function()
diff --git a/ormar/models/metaclass.py b/ormar/models/metaclass.py
index 36a3e74..64dfbeb 100644
--- a/ormar/models/metaclass.py
+++ b/ormar/models/metaclass.py
@@ -1,60 +1,63 @@
+import copy
+import sys
+import warnings
+from pathlib import Path
 from typing import (
+    TYPE_CHECKING,
     Any,
+    Callable,
     Dict,
     List,
     Optional,
     Set,
-    TYPE_CHECKING,
     Tuple,
     Type,
     Union,
     cast,
-    Callable,
 )
 
-import databases
 import pydantic
 import sqlalchemy
+from pydantic import field_serializer
+from pydantic._internal._generics import PydanticGenericMetadata
+from pydantic.fields import ComputedFieldInfo, FieldInfo
+from pydantic_core.core_schema import SerializerFunctionWrapHandler
 from sqlalchemy.sql.schema import ColumnCollectionConstraint
 
 import ormar  # noqa I100
 import ormar.fields.constraints
-from ormar.fields.constraints import UniqueColumns, IndexColumns, CheckColumns
 from ormar import ModelDefinitionError  # noqa I100
 from ormar.exceptions import ModelError
 from ormar.fields import BaseField
+from ormar.fields.constraints import CheckColumns, IndexColumns, UniqueColumns
 from ormar.fields.foreign_key import ForeignKeyField
 from ormar.fields.many_to_many import ManyToManyField
 from ormar.models.descriptors import (
     JsonDescriptor,
     PkDescriptor,
-    PropertyDescriptor,
     PydanticDescriptor,
     RelationDescriptor,
 )
 from ormar.models.descriptors.descriptors import BytesDescriptor
 from ormar.models.helpers import (
-    alias_manager,
-    check_required_meta_parameters,
+    check_required_config_parameters,
+    config_field_not_set,
     expand_reverse_relationships,
     extract_annotations_and_default_vals,
     get_potential_fields,
-    get_pydantic_field,
     merge_or_generate_pydantic_config,
-    meta_field_not_set,
-    populate_choices_validators,
+    modify_schema_example,
+    populate_config_sqlalchemy_table_if_required,
+    populate_config_tablename_columns_and_pk,
     populate_default_options_values,
-    populate_meta_sqlalchemy_table_if_required,
-    populate_meta_tablename_columns_and_pk,
     register_relation_in_alias_manager,
     remove_excluded_parent_fields,
     sqlalchemy_columns_from_model_fields,
 )
+from ormar.models.ormar_config import OrmarConfig
 from ormar.models.quick_access_views import quick_access_set
-from ormar.models.utils import Extra
 from ormar.queryset import FieldAccessor, QuerySet
-from ormar.relations.alias_manager import AliasManager
-from ormar.signals import Signal, SignalEmitter
+from ormar.signals import Signal
 
 if TYPE_CHECKING:  # pragma no cover
     from ormar import Model
@@ -64,32 +67,6 @@ CONFIG_KEY = "Config"
 PARSED_FIELDS_KEY = "__parsed_fields__"
 
 
-class ModelMeta:
-    """
-    Class used for type hinting.
-    Users can subclass this one for convenience but it's not required.
-    The only requirement is that ormar.Model has to have inner class with name Meta.
-    """
-
-    tablename: str
-    table: sqlalchemy.Table
-    metadata: sqlalchemy.MetaData
-    database: databases.Database
-    columns: List[sqlalchemy.Column]
-    constraints: List[ColumnCollectionConstraint]
-    pkname: str
-    model_fields: Dict[str, Union[BaseField, ForeignKeyField, ManyToManyField]]
-    alias_manager: AliasManager
-    property_fields: Set
-    signals: SignalEmitter
-    abstract: bool
-    requires_ref_update: bool
-    orders_by: List[str]
-    exclude_parent_fields: List[str]
-    extra: Extra
-    queryset_class: Type[QuerySet]
-
-
 def add_cached_properties(new_model: Type["Model"]) -> None:
     """
     Sets cached properties for both pydantic and ormar models.
@@ -108,15 +85,14 @@ def add_cached_properties(new_model: Type["Model"]) -> None:
     new_model._related_names = None
     new_model._through_names = None
     new_model._related_fields = None
-    new_model._pydantic_fields = {name for name in new_model.__fields__}
     new_model._json_fields = set()
     new_model._bytes_fields = set()
 
 
 def add_property_fields(new_model: Type["Model"], attrs: Dict) -> None:  # noqa: CCR001
     """
-    Checks class namespace for properties or functions with __property_field__.
-    If attribute have __property_field__ it was decorated with @property_field.
+    Checks class namespace for properties or functions with computed_field.
+    If attribute have decorator_info it was decorated with @computed_field.
 
     Functions like this are exposed in dict() (therefore also fastapi result).
     Names of property fields are cached for quicker access / extraction.
@@ -128,21 +104,22 @@ def add_property_fields(new_model: Type["Model"], attrs: Dict) -> None:  # noqa:
     """
     props = set()
     for var_name, value in attrs.items():
-        if isinstance(value, property):
-            value = value.fget
-        field_config = getattr(value, "__property_field__", None)
-        if field_config:
+        if hasattr(value, "decorator_info") and isinstance(
+            value.decorator_info, ComputedFieldInfo
+        ):
             props.add(var_name)
 
-    if meta_field_not_set(model=new_model, field_name="property_fields"):
-        new_model.Meta.property_fields = props
+    if config_field_not_set(model=new_model, field_name="property_fields"):
+        new_model.ormar_config.property_fields = props
     else:
-        new_model.Meta.property_fields = new_model.Meta.property_fields.union(props)
+        new_model.ormar_config.property_fields = (
+            new_model.ormar_config.property_fields.union(props)
+        )
 
 
 def register_signals(new_model: Type["Model"]) -> None:  # noqa: CCR001
     """
-    Registers on model's SignalEmmiter and sets pre defined signals.
+    Registers on model's SignalEmmiter and sets pre-defined signals.
     Predefined signals are (pre/post) + (save/update/delete).
 
     Signals are emitted in both model own methods and in selected queryset ones.
@@ -150,8 +127,8 @@ def register_signals(new_model: Type["Model"]) -> None:  # noqa: CCR001
     :param new_model: newly constructed model
     :type new_model: Model class
     """
-    if meta_field_not_set(model=new_model, field_name="signals"):
-        signals = SignalEmitter()
+    if config_field_not_set(model=new_model, field_name="signals"):
+        signals = new_model.ormar_config.signals
         signals.pre_save = Signal()
         signals.pre_update = Signal()
         signals.pre_delete = Signal()
@@ -163,7 +140,6 @@ def register_signals(new_model: Type["Model"]) -> None:  # noqa: CCR001
         signals.pre_relation_remove = Signal()
         signals.post_relation_remove = Signal()
         signals.post_bulk_update = Signal()
-        new_model.Meta.signals = signals
 
 
 def verify_constraint_names(
@@ -182,7 +158,9 @@ def verify_constraint_names(
     :type parent_value: List
     """
     new_aliases = {x.name: x.get_alias() for x in model_fields.values()}
-    old_aliases = {x.name: x.get_alias() for x in base_class.Meta.model_fields.values()}
+    old_aliases = {
+        x.name: x.get_alias() for x in base_class.ormar_config.model_fields.values()
+    }
     old_aliases.update(new_aliases)
     constraints_columns = [x._pending_colargs for x in parent_value]
     for column_set in constraints_columns:
@@ -224,11 +202,11 @@ def get_constraint_copy(
     return constructor(constraint)
 
 
-def update_attrs_from_base_meta(  # noqa: CCR001
+def update_attrs_from_base_config(  # noqa: CCR001
     base_class: "Model", attrs: Dict, model_fields: Dict
 ) -> None:
     """
-    Updates Meta parameters in child from parent if needed.
+    Updates OrmarConfig parameters in child from parent if needed.
 
     :param base_class: one of the parent classes
     :type base_class: Model or model parent class
@@ -240,9 +218,13 @@ def update_attrs_from_base_meta(  # noqa: CCR001
 
     params_to_update = ["metadata", "database", "constraints", "property_fields"]
     for param in params_to_update:
-        current_value = attrs.get("Meta", {}).__dict__.get(param, ormar.Undefined)
+        current_value = attrs.get("ormar_config", {}).__dict__.get(
+            param, ormar.Undefined
+        )
         parent_value = (
-            base_class.Meta.__dict__.get(param) if hasattr(base_class, "Meta") else None
+            base_class.ormar_config.__dict__.get(param)
+            if hasattr(base_class, "ormar_config")
+            else None
         )
         if parent_value:
             if param == "constraints":
@@ -255,7 +237,7 @@ def update_attrs_from_base_meta(  # noqa: CCR001
             if isinstance(current_value, list):
                 current_value.extend(parent_value)
             else:
-                setattr(attrs["Meta"], param, parent_value)
+                setattr(attrs["ormar_config"], param, parent_value)
 
 
 def copy_and_replace_m2m_through_model(  # noqa: CFQ002
@@ -264,7 +246,7 @@ def copy_and_replace_m2m_through_model(  # noqa: CFQ002
     table_name: str,
     parent_fields: Dict,
     attrs: Dict,
-    meta: ModelMeta,
+    ormar_config: OrmarConfig,
     base_class: Type["Model"],
 ) -> None:
     """
@@ -291,8 +273,8 @@ def copy_and_replace_m2m_through_model(  # noqa: CFQ002
     :type parent_fields: Dict
     :param attrs: new namespace for class being constructed
     :type attrs: Dict
-    :param meta: metaclass of currently created model
-    :type meta: ModelMeta
+    :param ormar_config: metaclass of currently created model
+    :type ormar_config: OrmarConfig
     """
     Field: Type[BaseField] = type(  # type: ignore
         field.__class__.__name__, (ManyToManyField, BaseField), {}
@@ -306,32 +288,51 @@ def copy_and_replace_m2m_through_model(  # noqa: CFQ002
         field.owner = base_class
         field.create_default_through_model()
         through_class = field.through
-    new_meta: ormar.ModelMeta = type(  # type: ignore
-        "Meta", (), dict(through_class.Meta.__dict__)
+    new_config = ormar.OrmarConfig(
+        tablename=through_class.ormar_config.tablename,
+        metadata=through_class.ormar_config.metadata,
+        database=through_class.ormar_config.database,
+        abstract=through_class.ormar_config.abstract,
+        exclude_parent_fields=through_class.ormar_config.exclude_parent_fields,
+        queryset_class=through_class.ormar_config.queryset_class,
+        extra=through_class.ormar_config.extra,
+        constraints=through_class.ormar_config.constraints,
+        order_by=through_class.ormar_config.orders_by,
+    )
+    new_config.table = through_class.ormar_config.pkname
+    new_config.pkname = through_class.ormar_config.pkname
+    new_config.alias_manager = through_class.ormar_config.alias_manager
+    new_config.signals = through_class.ormar_config.signals
+    new_config.requires_ref_update = through_class.ormar_config.requires_ref_update
+    new_config.model_fields = copy.deepcopy(through_class.ormar_config.model_fields)
+    new_config.property_fields = copy.deepcopy(
+        through_class.ormar_config.property_fields
     )
     copy_name = through_class.__name__ + attrs.get("__name__", "")
-    copy_through = type(copy_name, (ormar.Model,), {"Meta": new_meta})
-    new_meta.tablename += "_" + meta.tablename
+    copy_through = cast(
+        Type[ormar.Model], type(copy_name, (ormar.Model,), {"ormar_config": new_config})
+    )
     # create new table with copied columns but remove foreign keys
     # they will be populated later in expanding reverse relation
-    if hasattr(new_meta, "table"):
-        del new_meta.table
-    new_meta.model_fields = {
+    # if hasattr(new_config, "table"):
+    new_config.tablename += "_" + ormar_config.tablename
+    new_config.table = None
+    new_config.model_fields = {
         name: field
-        for name, field in new_meta.model_fields.items()
+        for name, field in new_config.model_fields.items()
         if not field.is_relation
     }
     _, columns = sqlalchemy_columns_from_model_fields(
-        new_meta.model_fields, copy_through
+        new_config.model_fields, copy_through
     )  # type: ignore
-    new_meta.columns = columns
-    populate_meta_sqlalchemy_table_if_required(new_meta)
+    new_config.columns = columns
+    populate_config_sqlalchemy_table_if_required(config=new_config)
     copy_field.through = copy_through
 
     parent_fields[field_name] = copy_field
 
-    if through_class.Meta.table in through_class.Meta.metadata:
-        through_class.Meta.metadata.remove(through_class.Meta.table)
+    if through_class.ormar_config.table in through_class.ormar_config.metadata:
+        through_class.ormar_config.metadata.remove(through_class.ormar_config.table)
 
 
 def copy_data_from_parent_model(  # noqa: CCR001
@@ -361,32 +362,32 @@ def copy_data_from_parent_model(  # noqa: CCR001
     :return: updated attrs and model_fields
     :rtype: Tuple[Dict, Dict]
     """
-    if attrs.get("Meta"):
-        if model_fields and not base_class.Meta.abstract:  # type: ignore
+    if attrs.get("ormar_config"):
+        if model_fields and not base_class.ormar_config.abstract:  # type: ignore
             raise ModelDefinitionError(
                 f"{curr_class.__name__} cannot inherit "
                 f"from non abstract class {base_class.__name__}"
             )
-        update_attrs_from_base_meta(
+        update_attrs_from_base_config(
             base_class=base_class,  # type: ignore
             attrs=attrs,
             model_fields=model_fields,
         )
         parent_fields: Dict = dict()
-        meta = attrs.get("Meta")
-        if not meta:  # pragma: no cover
+        ormar_config = attrs.get("ormar_config")
+        if not ormar_config:  # pragma: no cover
             raise ModelDefinitionError(
-                f"Model {curr_class.__name__} declared without Meta"
+                f"Model {curr_class.__name__} declared without ormar_config"
             )
         table_name = (
-            meta.tablename
-            if hasattr(meta, "tablename") and meta.tablename
+            ormar_config.tablename
+            if hasattr(ormar_config, "tablename") and ormar_config.tablename
             else attrs.get("__name__", "").lower() + "s"
         )
-        for field_name, field in base_class.Meta.model_fields.items():
+        for field_name, field in base_class.ormar_config.model_fields.items():
             if (
-                hasattr(meta, "exclude_parent_fields")
-                and field_name in meta.exclude_parent_fields
+                hasattr(ormar_config, "exclude_parent_fields")
+                and field_name in ormar_config.exclude_parent_fields
             ):
                 continue
             if field.is_multi:
@@ -397,7 +398,7 @@ def copy_data_from_parent_model(  # noqa: CCR001
                     table_name=table_name,
                     parent_fields=parent_fields,
                     attrs=attrs,
-                    meta=meta,
+                    ormar_config=ormar_config,
                     base_class=base_class,  # type: ignore
                 )
 
@@ -446,7 +447,7 @@ def extract_from_parents_definition(  # noqa: CCR001
     :return: updated attrs and model_fields
     :rtype: Tuple[Dict, Dict]
     """
-    if hasattr(base_class, "Meta"):
+    if hasattr(base_class, "ormar_config"):
         base_class = cast(Type["Model"], base_class)
         return copy_data_from_parent_model(
             base_class=base_class,
@@ -503,7 +504,7 @@ def update_attrs_and_fields(
 ) -> Dict:
     """
     Updates __annotations__, values of model fields (so pydantic FieldInfos)
-    as well as model.Meta.model_fields definitions from parents.
+    as well as model.ormar_config.model_fields definitions from parents.
 
     :param attrs: new namespace for class being constructed
     :type attrs: Dict
@@ -549,10 +550,42 @@ def add_field_descriptor(
         setattr(new_model, name, PydanticDescriptor(name=name))
 
 
-class ModelMetaclass(pydantic.main.ModelMetaclass):
+def get_serializer() -> Callable:
+    def serialize(
+        self: "Model",
+        value: Optional["Model"],
+        handler: SerializerFunctionWrapHandler,
+    ) -> Any:
+        """
+        Serialize a value if it's not expired weak reference.
+        """
+        try:
+            with warnings.catch_warnings():
+                warnings.filterwarnings(
+                    "ignore", message="Pydantic serializer warnings"
+                )
+                return handler(value)
+        except ReferenceError:
+            return None
+        except ValueError as exc:
+            if not str(exc).startswith("Circular reference"):
+                raise exc
+            return {value.ormar_config.pkname: value.pk} if value else None
+
+    return serialize
+
+
+class ModelMetaclass(pydantic._internal._model_construction.ModelMetaclass):
     def __new__(  # type: ignore # noqa: CCR001
-        mcs: "ModelMetaclass", name: str, bases: Any, attrs: dict
-    ) -> "ModelMetaclass":
+        mcs: "ModelMetaclass",
+        name: str,
+        bases: Any,
+        attrs: dict,
+        __pydantic_generic_metadata__: Union[PydanticGenericMetadata, None] = None,
+        __pydantic_reset_parent_namespace__: bool = True,
+        _create_model_module: Union[str, None] = None,
+        **kwargs,
+    ) -> type:
         """
         Metaclass used by ormar Models that performs configuration
         and build of ormar Models.
@@ -563,18 +596,19 @@ class ModelMetaclass(pydantic.main.ModelMetaclass):
         updates class namespace.
 
         Extracts settings and fields from parent classes.
-        Fetches methods decorated with @property_field decorator
+        Fetches methods decorated with @computed_field decorator
         to expose them later in dict().
 
         Construct parent pydantic Metaclass/ Model.
 
-        If class has Meta class declared (so actual ormar Models) it also:
+        If class has ormar_config declared (so actual ormar Models) it also:
 
         * populate sqlalchemy columns, pkname and tables from model_fields
         * register reverse relationships on related models
         * registers all relations in alias manager that populates table_prefixes
         * exposes alias manager on each Model
         * creates QuerySet for each model and exposes it on a class
+        * sets custom serializers for relation models
 
         :param name: name of current class
         :type name: str
@@ -593,63 +627,74 @@ class ModelMetaclass(pydantic.main.ModelMetaclass):
             attrs, model_fields = extract_from_parents_definition(
                 base_class=base, curr_class=mcs, attrs=attrs, model_fields=model_fields
             )
-        new_model = super().__new__(mcs, name, bases, attrs)  # type: ignore
+        if "ormar_config" in attrs:
+            attrs["model_config"]["ignored_types"] = (OrmarConfig,)
+            attrs["model_config"]["from_attributes"] = True
+            for field_name, field in model_fields.items():
+                if field.is_relation:
+                    decorator = field_serializer(
+                        field_name, mode="wrap", check_fields=False
+                    )(get_serializer())
+                    attrs[f"serialize_{field_name}"] = decorator
+
+        new_model = super().__new__(
+            mcs,  # type: ignore
+            name,
+            bases,
+            attrs,
+            __pydantic_generic_metadata__=__pydantic_generic_metadata__,
+            __pydantic_reset_parent_namespace__=__pydantic_reset_parent_namespace__,
+            _create_model_module=_create_model_module,
+            **kwargs,
+        )
 
         add_cached_properties(new_model)
 
-        if hasattr(new_model, "Meta"):
+        if hasattr(new_model, "ormar_config"):
             populate_default_options_values(new_model, model_fields)
-            check_required_meta_parameters(new_model)
+            check_required_config_parameters(new_model)
             add_property_fields(new_model, attrs)
             register_signals(new_model=new_model)
-            populate_choices_validators(new_model)
+            modify_schema_example(model=new_model)
 
-            if not new_model.Meta.abstract:
-                new_model = populate_meta_tablename_columns_and_pk(name, new_model)
-                populate_meta_sqlalchemy_table_if_required(new_model.Meta)
+            if not new_model.ormar_config.abstract:
+                new_model = populate_config_tablename_columns_and_pk(name, new_model)
+                populate_config_sqlalchemy_table_if_required(new_model.ormar_config)
                 expand_reverse_relationships(new_model)
-                # TODO: iterate only related fields
-                for field_name, field in new_model.Meta.model_fields.items():
+                for field_name, field in new_model.ormar_config.model_fields.items():
                     register_relation_in_alias_manager(field=field)
                     add_field_descriptor(
                         name=field_name, field=field, new_model=new_model
                     )
 
                 if (
-                    new_model.Meta.pkname
-                    and new_model.Meta.pkname not in attrs["__annotations__"]
-                    and new_model.Meta.pkname not in new_model.__fields__
+                    new_model.ormar_config.pkname
+                    and new_model.ormar_config.pkname not in attrs["__annotations__"]
+                    and new_model.ormar_config.pkname not in new_model.model_fields
                 ):
-                    field_name = new_model.Meta.pkname
-                    attrs["__annotations__"][field_name] = Optional[int]  # type: ignore
-                    attrs[field_name] = None
-                    new_model.__fields__[field_name] = get_pydantic_field(
-                        field_name=field_name, model=new_model
-                    )
-                new_model.Meta.alias_manager = alias_manager
-
-                for item in new_model.Meta.property_fields:
-                    function = getattr(new_model, item)
-                    setattr(
-                        new_model,
-                        item,
-                        PropertyDescriptor(name=item, function=function),
+                    field_name = new_model.ormar_config.pkname
+                    new_model.model_fields[field_name] = (
+                        FieldInfo.from_annotated_attribute(
+                            Optional[int],  # type: ignore
+                            None,
+                        )
                     )
+                    new_model.model_rebuild(force=True)
 
-                new_model.pk = PkDescriptor(name=new_model.Meta.pkname)
+                new_model.pk = PkDescriptor(name=new_model.ormar_config.pkname)
                 remove_excluded_parent_fields(new_model)
 
         return new_model
 
     @property
     def objects(cls: Type["T"]) -> "QuerySet[T]":  # type: ignore
-        if cls.Meta.requires_ref_update:
+        if cls.ormar_config.requires_ref_update:
             raise ModelError(
                 f"Model {cls.get_name()} has not updated "
                 f"ForwardRefs. \nBefore using the model you "
                 f"need to call update_forward_refs()."
             )
-        return cls.Meta.queryset_class(model_cls=cls)
+        return cls.ormar_config.queryset_class(model_cls=cls)
 
     def __getattr__(self, item: str) -> Any:
         """
@@ -661,10 +706,19 @@ class ModelMetaclass(pydantic.main.ModelMetaclass):
         :return: FieldAccessor for given field
         :rtype: FieldAccessor
         """
+        # Ugly workaround for name shadowing warnings in pydantic
+        frame = sys._getframe(1)
+        file_name = Path(frame.f_code.co_filename)
+        if (
+            frame.f_code.co_name == "collect_model_fields"
+            and file_name.name == "_fields.py"
+            and file_name.parent.parent.name == "pydantic"
+        ):
+            raise AttributeError()
         if item == "pk":
-            item = self.Meta.pkname
-        if item in object.__getattribute__(self, "Meta").model_fields:
-            field = self.Meta.model_fields.get(item)
+            item = self.ormar_config.pkname
+        if item in object.__getattribute__(self, "ormar_config").model_fields:
+            field = self.ormar_config.model_fields.get(item)
             if field.is_relation:
                 return FieldAccessor(
                     source_model=cast(Type["Model"], self),
diff --git a/ormar/models/mixins/__init__.py b/ormar/models/mixins/__init__.py
index e605ee8..edb5852 100644
--- a/ormar/models/mixins/__init__.py
+++ b/ormar/models/mixins/__init__.py
@@ -4,6 +4,7 @@ All mixins are combined into ModelTableProxy which is one of the parents of Mode
 The split into mixins was done to ease the maintainability of the proxy class, as
 it became quite complicated over time.
 """
+
 from ormar.models.mixins.alias_mixin import AliasMixin
 from ormar.models.mixins.excludable_mixin import ExcludableMixin
 from ormar.models.mixins.merge_mixin import MergeModelMixin
diff --git a/ormar/models/mixins/alias_mixin.py b/ormar/models/mixins/alias_mixin.py
index 2d98657..2f808cd 100644
--- a/ormar/models/mixins/alias_mixin.py
+++ b/ormar/models/mixins/alias_mixin.py
@@ -1,4 +1,4 @@
-from typing import Dict, TYPE_CHECKING
+from typing import TYPE_CHECKING, Dict
 
 
 class AliasMixin:
@@ -7,9 +7,9 @@ class AliasMixin:
     """
 
     if TYPE_CHECKING:  # pragma: no cover
-        from ormar import ModelMeta
+        from ormar.models.ormar_config import OrmarConfig
 
-        Meta: ModelMeta
+        ormar_config: OrmarConfig
 
     @classmethod
     def get_column_alias(cls, field_name: str) -> str:
@@ -21,7 +21,7 @@ class AliasMixin:
         :return: alias (db name) if set, otherwise passed name
         :rtype: str
         """
-        field = cls.Meta.model_fields.get(field_name)
+        field = cls.ormar_config.model_fields.get(field_name)
         return field.get_alias() if field is not None else field_name
 
     @classmethod
@@ -34,7 +34,7 @@ class AliasMixin:
         :return: field name if set, otherwise passed alias (db name)
         :rtype: str
         """
-        for field_name, field in cls.Meta.model_fields.items():
+        for field_name, field in cls.ormar_config.model_fields.items():
             if field.get_alias() == alias:
                 return field_name
         return alias  # if not found it's not an alias but actual name
@@ -50,7 +50,7 @@ class AliasMixin:
         :return: dict with aliases and their values
         :rtype: Dict
         """
-        for field_name, field in cls.Meta.model_fields.items():
+        for field_name, field in cls.ormar_config.model_fields.items():
             if field_name in new_kwargs:
                 new_kwargs[field.get_alias()] = new_kwargs.pop(field_name)
         return new_kwargs
@@ -66,7 +66,7 @@ class AliasMixin:
         :return: dict with fields names and their values
         :rtype: Dict
         """
-        for field_name, field in cls.Meta.model_fields.items():
+        for field_name, field in cls.ormar_config.model_fields.items():
             if field.get_alias() and field.get_alias() in new_kwargs:
                 new_kwargs[field_name] = new_kwargs.pop(field.get_alias())
         return new_kwargs
diff --git a/ormar/models/mixins/excludable_mixin.py b/ormar/models/mixins/excludable_mixin.py
index d7019b7..b6151ad 100644
--- a/ormar/models/mixins/excludable_mixin.py
+++ b/ormar/models/mixins/excludable_mixin.py
@@ -1,13 +1,13 @@
 from typing import (
+    TYPE_CHECKING,
     AbstractSet,
     Any,
     Dict,
     List,
     Mapping,
+    Optional,
     Set,
-    TYPE_CHECKING,
     Type,
-    TypeVar,
     Union,
     cast,
 )
@@ -18,7 +18,6 @@ from ormar.models.mixins.relation_mixin import RelationMixin
 if TYPE_CHECKING:  # pragma no cover
     from ormar import Model
 
-    T = TypeVar("T", bound=Model)
     IntStr = Union[int, str]
     AbstractSetIntStr = AbstractSet[IntStr]
     MappingIntStrAny = Mapping[IntStr, Any]
@@ -35,7 +34,7 @@ class ExcludableMixin(RelationMixin):
 
     @staticmethod
     def get_child(
-        items: Union[Set, Dict, None], key: str = None
+        items: Union[Set, Dict, None], key: Optional[str] = None
     ) -> Union[Set, Dict, None]:
         """
         Used to get nested dictionaries keys if they exists otherwise returns
@@ -71,9 +70,9 @@ class ExcludableMixin(RelationMixin):
         :rtype: List[str]
         """
         pk_alias = (
-            model.get_column_alias(model.Meta.pkname)
+            model.get_column_alias(model.ormar_config.pkname)
             if use_alias
-            else model.Meta.pkname
+            else model.ormar_config.pkname
         )
         if pk_alias not in columns:
             columns.append(pk_alias)
@@ -113,11 +112,11 @@ class ExcludableMixin(RelationMixin):
         model_excludable = excludable.get(model_cls=model, alias=alias)  # type: ignore
         columns = [
             model.get_column_name_from_alias(col.name) if not use_alias else col.name
-            for col in model.Meta.table.columns
+            for col in model.ormar_config.table.columns
         ]
         field_names = [
             model.get_column_name_from_alias(col.name)
-            for col in model.Meta.table.columns
+            for col in model.ormar_config.table.columns
         ]
         if model_excludable.include:
             columns = [
@@ -181,7 +180,7 @@ class ExcludableMixin(RelationMixin):
         :rtype: Set
         """
         if exclude_primary_keys:
-            exclude.add(cls.Meta.pkname)
+            exclude.add(cls.ormar_config.pkname)
         if exclude_through_models:
             exclude = exclude.union(cls.extract_through_names())
         return exclude
@@ -219,6 +218,6 @@ class ExcludableMixin(RelationMixin):
             fields_to_exclude = fields_to_exclude.union(
                 model_excludable.exclude.intersection(fields_names)
             )
-        fields_to_exclude = fields_to_exclude - {cls.Meta.pkname}
+        fields_to_exclude = fields_to_exclude - {cls.ormar_config.pkname}
 
         return fields_to_exclude
diff --git a/ormar/models/mixins/merge_mixin.py b/ormar/models/mixins/merge_mixin.py
index 7ef2077..3555c34 100644
--- a/ormar/models/mixins/merge_mixin.py
+++ b/ormar/models/mixins/merge_mixin.py
@@ -1,4 +1,4 @@
-from typing import Dict, List, Optional, TYPE_CHECKING, cast
+from typing import TYPE_CHECKING, Dict, List, Optional, cast
 
 import ormar
 from ormar.queryset.utils import translate_list_to_dict
@@ -69,7 +69,7 @@ class MergeModelMixin:
 
     @classmethod
     def merge_two_instances(
-        cls, one: "Model", other: "Model", relation_map: Dict = None
+        cls, one: "Model", other: "Model", relation_map: Optional[Dict] = None
     ) -> "Model":
         """
         Merges current (other) Model and previous one (one) and returns the current
diff --git a/ormar/models/mixins/prefetch_mixin.py b/ormar/models/mixins/prefetch_mixin.py
index b159850..61eb29d 100644
--- a/ormar/models/mixins/prefetch_mixin.py
+++ b/ormar/models/mixins/prefetch_mixin.py
@@ -1,4 +1,4 @@
-from typing import Callable, Dict, List, TYPE_CHECKING, Tuple, Type, cast
+from typing import TYPE_CHECKING, Callable, Dict, List, Tuple, Type, cast
 
 from ormar.models.mixins.relation_mixin import RelationMixin
 
@@ -38,15 +38,17 @@ class PrefetchQueryMixin(RelationMixin):
         :rtype: Tuple[Type[Model], str]
         """
         if reverse:
-            field_name = parent_model.Meta.model_fields[related].get_related_name()
-            field = target_model.Meta.model_fields[field_name]
+            field_name = parent_model.ormar_config.model_fields[
+                related
+            ].get_related_name()
+            field = target_model.ormar_config.model_fields[field_name]
             if field.is_multi:
                 field = cast("ManyToManyField", field)
                 field_name = field.default_target_field_name()
-                sub_field = field.through.Meta.model_fields[field_name]
+                sub_field = field.through.ormar_config.model_fields[field_name]
                 return field.through, sub_field.get_alias()
             return target_model, field.get_alias()
-        target_field = target_model.get_column_alias(target_model.Meta.pkname)
+        target_field = target_model.get_column_alias(target_model.ormar_config.pkname)
         return target_model, target_field
 
     @staticmethod
@@ -70,11 +72,11 @@ class PrefetchQueryMixin(RelationMixin):
         :rtype:
         """
         if reverse:
-            column_name = parent_model.Meta.pkname
+            column_name = parent_model.ormar_config.pkname
             return (
                 parent_model.get_column_alias(column_name) if use_raw else column_name
             )
-        column = parent_model.Meta.model_fields[related]
+        column = parent_model.ormar_config.model_fields[related]
         return column.get_alias() if use_raw else column.name
 
     @classmethod
@@ -93,7 +95,7 @@ class PrefetchQueryMixin(RelationMixin):
             return cls.get_name()
         if target_field.virtual:
             return target_field.get_related_name()
-        return target_field.to.Meta.pkname
+        return target_field.to.ormar_config.pkname
 
     @classmethod
     def get_filtered_names_to_extract(cls, prefetch_dict: Dict) -> List:
diff --git a/ormar/models/mixins/pydantic_mixin.py b/ormar/models/mixins/pydantic_mixin.py
index 5d186bb..bd2e1a6 100644
--- a/ormar/models/mixins/pydantic_mixin.py
+++ b/ormar/models/mixins/pydantic_mixin.py
@@ -2,37 +2,44 @@ import copy
 import string
 from random import choices
 from typing import (
+    TYPE_CHECKING,
     Any,
     Callable,
     Dict,
     List,
     Optional,
     Set,
-    TYPE_CHECKING,
+    Tuple,
     Type,
     Union,
     cast,
 )
 
 import pydantic
-from pydantic.fields import ModelField
+from pydantic import BaseModel
+from pydantic._internal._decorators import DecoratorInfos
+from pydantic.fields import FieldInfo
 
+from ormar.fields import BaseField, ForeignKeyField, ManyToManyField
 from ormar.models.mixins.relation_mixin import RelationMixin  # noqa: I100, I202
 from ormar.queryset.utils import translate_list_to_dict
 
 
 class PydanticMixin(RelationMixin):
-
     __cache__: Dict[str, Type[pydantic.BaseModel]] = {}
 
     if TYPE_CHECKING:  # pragma: no cover
-        __fields__: Dict[str, ModelField]
+        __pydantic_decorators__: DecoratorInfos
+        model_fields: Dict[str, FieldInfo]
         _skip_ellipsis: Callable
         _get_not_excluded_fields: Callable
 
     @classmethod
     def get_pydantic(
-        cls, *, include: Union[Set, Dict] = None, exclude: Union[Set, Dict] = None
+        cls,
+        *,
+        include: Union[Set, Dict, None] = None,
+        exclude: Union[Set, Dict, None] = None,
     ) -> Type[pydantic.BaseModel]:
         """
         Returns a pydantic model out of ormar model.
@@ -56,8 +63,8 @@ class PydanticMixin(RelationMixin):
     def _convert_ormar_to_pydantic(
         cls,
         relation_map: Dict[str, Any],
-        include: Union[Set, Dict] = None,
-        exclude: Union[Set, Dict] = None,
+        include: Union[Set, Dict, None] = None,
+        exclude: Union[Set, Dict, None] = None,
     ) -> Type[pydantic.BaseModel]:
         if include and isinstance(include, Set):
             include = translate_list_to_dict(include)
@@ -66,10 +73,12 @@ class PydanticMixin(RelationMixin):
         fields_dict: Dict[str, Any] = dict()
         defaults: Dict[str, Any] = dict()
         fields_to_process = cls._get_not_excluded_fields(
-            fields={*cls.Meta.model_fields.keys()}, include=include, exclude=exclude
+            fields={*cls.ormar_config.model_fields.keys()},
+            include=include,
+            exclude=exclude,
         )
         fields_to_process.sort(
-            key=lambda x: list(cls.Meta.model_fields.keys()).index(x)
+            key=lambda x: list(cls.ormar_config.model_fields.keys()).index(x)
         )
 
         cache_key = f"{cls.__name__}_{str(include)}_{str(exclude)}"
@@ -105,51 +114,84 @@ class PydanticMixin(RelationMixin):
         exclude: Union[Set, Dict, None],
         relation_map: Dict[str, Any],
     ) -> Any:
-        field = cls.Meta.model_fields[name]
+        field = cls.ormar_config.model_fields[name]
         target: Any = None
-        if field.is_relation and name in relation_map:  # type: ignore
-            target = field.to._convert_ormar_to_pydantic(
-                include=cls._skip_ellipsis(include, name),
-                exclude=cls._skip_ellipsis(exclude, name),
-                relation_map=cls._skip_ellipsis(
-                    relation_map, name, default_return=dict()
-                ),
+        if field.is_relation and name in relation_map:
+            target, default = cls._determined_included_relation_field_type(
+                name=name,
+                field=field,
+                include=include,
+                exclude=exclude,
+                defaults=defaults,
+                relation_map=relation_map,
             )
-            if field.is_multi or field.virtual:
-                target = List[target]  # type: ignore
         elif not field.is_relation:
-            defaults[name] = cls.__fields__[name].field_info
+            defaults[name] = cls.model_fields[name].default
             target = field.__type__
         if target is not None and field.nullable:
             target = Optional[target]
         return target
 
+    @classmethod
+    def _determined_included_relation_field_type(
+        cls,
+        name: str,
+        field: Union[BaseField, ForeignKeyField, ManyToManyField],
+        include: Union[Set, Dict, None],
+        exclude: Union[Set, Dict, None],
+        defaults: Dict,
+        relation_map: Dict[str, Any],
+    ) -> Tuple[Type[BaseModel], Dict]:
+        target = field.to._convert_ormar_to_pydantic(
+            include=cls._skip_ellipsis(include, name),
+            exclude=cls._skip_ellipsis(exclude, name),
+            relation_map=cls._skip_ellipsis(relation_map, name, default_return=dict()),
+        )
+        if field.is_multi or field.virtual:
+            target = List[target]  # type: ignore
+        if field.nullable:
+            defaults[name] = None
+        return target, defaults
+
     @classmethod
     def _copy_field_validators(cls, model: Type[pydantic.BaseModel]) -> None:
         """
         Copy field validators from ormar model to generated pydantic model.
         """
-        for field_name, field in model.__fields__.items():
-            if (
-                field_name not in cls.__fields__
-                or cls.Meta.model_fields[field_name].is_relation
-            ):
-                continue
-            validators = cls.__fields__[field_name].validators
-            already_attached = [
-                validator.__wrapped__ for validator in field.validators  # type: ignore
-            ]
-            validators_to_copy = [
-                validator
-                for validator in validators
-                if validator.__wrapped__ not in already_attached  # type: ignore
-            ]
-            field.validators.extend(copy.deepcopy(validators_to_copy))
-            class_validators = cls.__fields__[field_name].class_validators
-            field.class_validators.update(copy.deepcopy(class_validators))
-            field.pre_validators = copy.deepcopy(
-                cls.__fields__[field_name].pre_validators
-            )
-            field.post_validators = copy.deepcopy(
-                cls.__fields__[field_name].post_validators
-            )
+        filed_names = list(model.model_fields.keys())
+        cls.copy_selected_validators_type(
+            model=model, fields=filed_names, validator_type="field_validators"
+        )
+        cls.copy_selected_validators_type(
+            model=model, fields=filed_names, validator_type="validators"
+        )
+
+        class_validators = cls.__pydantic_decorators__.root_validators
+        model.__pydantic_decorators__.root_validators.update(
+            copy.deepcopy(class_validators)
+        )
+        model_validators = cls.__pydantic_decorators__.model_validators
+        model.__pydantic_decorators__.model_validators.update(
+            copy.deepcopy(model_validators)
+        )
+        model.model_rebuild(force=True)
+
+    @classmethod
+    def copy_selected_validators_type(
+        cls, model: Type[pydantic.BaseModel], fields: List[str], validator_type: str
+    ) -> None:
+        """
+        Copy field validators from ormar model to generated pydantic model.
+        """
+        validators = getattr(cls.__pydantic_decorators__, validator_type)
+        for name, decorator in validators.items():
+            if any(field_name in decorator.info.fields for field_name in fields):
+                copied_decorator = copy.deepcopy(decorator)
+                copied_decorator.info.fields = [
+                    field_name
+                    for field_name in decorator.info.fields
+                    if field_name in fields
+                ]
+                getattr(model.__pydantic_decorators__, validator_type)[
+                    name
+                ] = copied_decorator
diff --git a/ormar/models/mixins/relation_mixin.py b/ormar/models/mixins/relation_mixin.py
index 3f9521c..cf2a0af 100644
--- a/ormar/models/mixins/relation_mixin.py
+++ b/ormar/models/mixins/relation_mixin.py
@@ -1,4 +1,4 @@
-from typing import Callable, Dict, List, Optional, Set, TYPE_CHECKING, cast
+from typing import TYPE_CHECKING, Callable, Dict, List, Optional, Set, cast
 
 from ormar import BaseField, ForeignKeyField
 from ormar.models.traversible import NodeList
@@ -10,9 +10,9 @@ class RelationMixin:
     """
 
     if TYPE_CHECKING:  # pragma no cover
-        from ormar import ModelMeta
+        from ormar.models.ormar_config import OrmarConfig
 
-        Meta: ModelMeta
+        ormar_config: OrmarConfig
         __relation_map__: Optional[List[str]]
         _related_names: Optional[Set]
         _through_names: Optional[Set]
@@ -29,7 +29,9 @@ class RelationMixin:
         """
         related_names = cls.extract_related_names()
         self_fields = {
-            name for name in cls.Meta.model_fields.keys() if name not in related_names
+            name
+            for name in cls.ormar_config.model_fields.keys()
+            if name not in related_names
         }
         return self_fields
 
@@ -47,7 +49,9 @@ class RelationMixin:
 
         related_fields = []
         for name in cls.extract_related_names().union(cls.extract_through_names()):
-            related_fields.append(cast("ForeignKeyField", cls.Meta.model_fields[name]))
+            related_fields.append(
+                cast("ForeignKeyField", cls.ormar_config.model_fields[name])
+            )
         cls._related_fields = related_fields
 
         return related_fields
@@ -64,7 +68,7 @@ class RelationMixin:
             return cls._through_names
 
         related_names = set()
-        for name, field in cls.Meta.model_fields.items():
+        for name, field in cls.ormar_config.model_fields.items():
             if isinstance(field, BaseField) and field.is_through:
                 related_names.add(name)
 
@@ -84,7 +88,7 @@ class RelationMixin:
             return cls._related_names
 
         related_names = set()
-        for name, field in cls.Meta.model_fields.items():
+        for name, field in cls.ormar_config.model_fields.items():
             if (
                 isinstance(field, BaseField)
                 and field.is_relation
@@ -108,16 +112,16 @@ class RelationMixin:
         related_names = {
             name
             for name in related_names
-            if cls.Meta.model_fields[name].is_valid_uni_relation()
+            if cls.ormar_config.model_fields[name].is_valid_uni_relation()
         }
         return related_names
 
     @classmethod
     def _iterate_related_models(  # noqa: CCR001
         cls,
-        node_list: NodeList = None,
-        parsed_map: Dict = None,
-        source_relation: str = None,
+        node_list: Optional[NodeList] = None,
+        parsed_map: Optional[Dict] = None,
+        source_relation: Optional[str] = None,
         recurrent: bool = False,
     ) -> List[str]:
         """
@@ -139,7 +143,7 @@ class RelationMixin:
         processed_relations: List[str] = []
         for relation in relations:
             if not current_node.visited(relation):
-                target_model = cls.Meta.model_fields[relation].to
+                target_model = cls.ormar_config.model_fields[relation].to
                 node_list.add(
                     node_class=target_model,
                     relation_name=relation,
diff --git a/ormar/models/mixins/save_mixin.py b/ormar/models/mixins/save_mixin.py
index 46ef451..e759499 100644
--- a/ormar/models/mixins/save_mixin.py
+++ b/ormar/models/mixins/save_mixin.py
@@ -2,6 +2,7 @@ import base64
 import uuid
 from enum import Enum
 from typing import (
+    TYPE_CHECKING,
     Any,
     Callable,
     Collection,
@@ -9,11 +10,11 @@ from typing import (
     List,
     Optional,
     Set,
-    TYPE_CHECKING,
     cast,
 )
 
-import pydantic
+from pydantic.plugin._schema_validator import create_schema_validator
+from pydantic_core import CoreSchema, SchemaValidator
 
 import ormar  # noqa: I100, I202
 from ormar.exceptions import ModelPersistenceError
@@ -31,11 +32,11 @@ class SavePrepareMixin(RelationMixin, AliasMixin):
     """
 
     if TYPE_CHECKING:  # pragma: nocover
-        _choices_fields: Optional[Set]
         _skip_ellipsis: Callable
         _json_fields: Set[str]
         _bytes_fields: Set[str]
-        __fields__: Dict[str, pydantic.fields.ModelField]
+        __pydantic_core_schema__: CoreSchema
+        __ormar_fields_validators__: Optional[Dict[str, SchemaValidator]]
 
     @classmethod
     def prepare_model_to_save(cls, new_kwargs: dict) -> dict:
@@ -95,9 +96,7 @@ class SavePrepareMixin(RelationMixin, AliasMixin):
         :return: dictionary of model that is about to be saved
         :rtype: Dict[str, str]
         """
-        ormar_fields = {
-            k for k, v in cls.Meta.model_fields.items() if not v.pydantic_only
-        }
+        ormar_fields = {k for k, v in cls.ormar_config.model_fields.items()}
         new_kwargs = {k: v for k, v in new_kwargs.items() if k in ormar_fields}
         return new_kwargs
 
@@ -112,8 +111,8 @@ class SavePrepareMixin(RelationMixin, AliasMixin):
         :return: dictionary of model that is about to be saved
         :rtype: Dict[str, str]
         """
-        pkname = cls.Meta.pkname
-        pk = cls.Meta.model_fields[pkname]
+        pkname = cls.ormar_config.pkname
+        pk = cls.ormar_config.model_fields[pkname]
         if new_kwargs.get(pkname, ormar.Undefined) is None and (
             pk.nullable or pk.autoincrement
         ):
@@ -131,7 +130,7 @@ class SavePrepareMixin(RelationMixin, AliasMixin):
         :return: dictionary of model that is about to be saved
         :rtype: Dict
         """
-        for name, field in cls.Meta.model_fields.items():
+        for name, field in cls.ormar_config.model_fields.items():
             if field.__type__ == uuid.UUID and name in model_dict:
                 parsers = {"string": lambda x: str(x), "hex": lambda x: "%.32x" % x.int}
                 uuid_format = field.column_type.uuid_format
@@ -153,8 +152,8 @@ class SavePrepareMixin(RelationMixin, AliasMixin):
         for field in cls.extract_related_names():
             field_value = model_dict.get(field, None)
             if field_value is not None:
-                target_field = cls.Meta.model_fields[field]
-                target_pkname = target_field.to.Meta.pkname
+                target_field = cls.ormar_config.model_fields[field]
+                target_pkname = target_field.to.ormar_config.pkname
                 if isinstance(field_value, ormar.Model):  # pragma: no cover
                     pk_value = getattr(field_value, target_pkname)
                     if not pk_value:
@@ -187,7 +186,7 @@ class SavePrepareMixin(RelationMixin, AliasMixin):
         """
         bytes_base64_fields = {
             name
-            for name, field in cls.Meta.model_fields.items()
+            for name, field in cls.ormar_config.model_fields.items()
             if field.represent_as_base64_str
         }
         for key, value in model_dict.items():
@@ -227,12 +226,8 @@ class SavePrepareMixin(RelationMixin, AliasMixin):
         :return: dictionary of model that is about to be saved
         :rtype: Dict
         """
-        for field_name, field in cls.Meta.model_fields.items():
-            if (
-                field_name not in new_kwargs
-                and field.has_default(use_server=False)
-                and not field.pydantic_only
-            ):
+        for field_name, field in cls.ormar_config.model_fields.items():
+            if field_name not in new_kwargs and field.has_default(use_server=False):
                 new_kwargs[field_name] = field.get_default()
             # clear fields with server_default set as None
             if (
@@ -243,7 +238,7 @@ class SavePrepareMixin(RelationMixin, AliasMixin):
         return new_kwargs
 
     @classmethod
-    def validate_choices(cls, new_kwargs: Dict) -> Dict:
+    def validate_enums(cls, new_kwargs: Dict) -> Dict:
         """
         Receives dictionary of model that is about to be saved and validates the
         fields with choices set to see if the value is allowed.
@@ -253,23 +248,47 @@ class SavePrepareMixin(RelationMixin, AliasMixin):
         :return: dictionary of model that is about to be saved
         :rtype: Dict
         """
-        if not cls._choices_fields:
-            return new_kwargs
-
-        fields_to_check = [
-            field
-            for field in cls.Meta.model_fields.values()
-            if field.name in cls._choices_fields and field.name in new_kwargs
-        ]
-        for field in fields_to_check:
-            if new_kwargs[field.name] not in field.choices:
-                raise ValueError(
-                    f"{field.name}: '{new_kwargs[field.name]}' "
-                    f"not in allowed choices set:"
-                    f" {field.choices}"
-                )
+        validators = cls._build_individual_schema_validator()
+        for key, value in new_kwargs.items():
+            if key in validators:
+                validators[key].validate_python(value)
         return new_kwargs
 
+    @classmethod
+    def _build_individual_schema_validator(cls) -> Any:
+        if cls.__ormar_fields_validators__ is not None:
+            return cls.__ormar_fields_validators__
+        field_validators = {}
+        for key, field in cls._extract_pydantic_fields().items():
+            if cls.__pydantic_core_schema__["type"] == "definitions":
+                schema = {
+                    "type": "definitions",
+                    "schema": field["schema"],
+                    "definitions": cls.__pydantic_core_schema__["definitions"],
+                }
+            else:
+                schema = field["schema"]
+            field_validators[key] = create_schema_validator(
+                schema, cls, cls.__module__, cls.__qualname__, "BaseModel"
+            )
+        cls.__ormar_fields_validators__ = field_validators
+        return cls.__ormar_fields_validators__
+
+    @classmethod
+    def _extract_pydantic_fields(cls) -> Any:
+        if cls.__pydantic_core_schema__["type"] == "model":
+            return cls.__pydantic_core_schema__["schema"]["fields"]
+        elif cls.__pydantic_core_schema__["type"] == "definitions":
+            main_schema = cls.__pydantic_core_schema__["schema"]
+            if "schema_ref" in main_schema:
+                reference_id = main_schema["schema_ref"]
+                return next(
+                    ref
+                    for ref in cls.__pydantic_core_schema__["definitions"]
+                    if ref["ref"] == reference_id
+                )["schema"]["fields"]
+            return main_schema["schema"]["fields"]
+
     @staticmethod
     async def _upsert_model(
         instance: "Model",
@@ -329,12 +348,12 @@ class SavePrepareMixin(RelationMixin, AliasMixin):
         :param previous_model: previous model from which method came
         :type previous_model: Model
         """
-        through_name = previous_model.Meta.model_fields[
+        through_name = previous_model.ormar_config.model_fields[
             relation_field.name
         ].through.get_name()
         through = getattr(instance, through_name)
         if through:
-            through_dict = through.dict(exclude=through.extract_related_names())
+            through_dict = through.model_dump(exclude=through.extract_related_names())
         else:
             through_dict = {}
         await getattr(
diff --git a/ormar/models/model.py b/ormar/models/model.py
index 7ff8e63..f527485 100644
--- a/ormar/models/model.py
+++ b/ormar/models/model.py
@@ -1,9 +1,8 @@
-from typing import Any, Dict, List, Optional, Set, TYPE_CHECKING, TypeVar, Union
+from typing import TYPE_CHECKING, Any, Dict, List, Optional, Set, TypeVar, Union
 
 import ormar.queryset  # noqa I100
 from ormar.exceptions import ModelPersistenceError, NoMatch
 from ormar.models import NewBaseModel  # noqa I100
-from ormar.models.metaclass import ModelMeta
 from ormar.models.model_row import ModelRow
 from ormar.queryset.utils import subtract_dict, translate_list_to_dict
 
@@ -11,17 +10,18 @@ T = TypeVar("T", bound="Model")
 
 if TYPE_CHECKING:  # pragma: no cover
     from ormar import ForeignKeyField
+    from ormar.models.ormar_config import OrmarConfig
 
 
 class Model(ModelRow):
     __abstract__ = False
     if TYPE_CHECKING:  # pragma nocover
-        Meta: ModelMeta
+        ormar_config: OrmarConfig
 
     def __repr__(self) -> str:  # pragma nocover
         _repr = {
             k: getattr(self, k)
-            for k, v in self.Meta.model_fields.items()
+            for k, v in self.ormar_config.model_fields.items()
             if not v.skip_field
         }
         return f"{self.__class__.__name__}({str(_repr)})"
@@ -40,8 +40,8 @@ class Model(ModelRow):
 
         force_save = kwargs.pop("__force_save__", False)
         if force_save:
-            expr = self.Meta.table.select().where(self.pk_column == self.pk)
-            row = await self.Meta.database.fetch_one(expr)
+            expr = self.ormar_config.table.select().where(self.pk_column == self.pk)
+            row = await self.ormar_config.database.fetch_one(expr)
             if not row:
                 return await self.save()
             return await self.update(**kwargs)
@@ -76,8 +76,11 @@ class Model(ModelRow):
         await self.signals.pre_save.send(sender=self.__class__, instance=self)
         self_fields = self._extract_model_db_fields()
 
-        if not self.pk and self.Meta.model_fields[self.Meta.pkname].autoincrement:
-            self_fields.pop(self.Meta.pkname, None)
+        if (
+            not self.pk
+            and self.ormar_config.model_fields[self.ormar_config.pkname].autoincrement
+        ):
+            self_fields.pop(self.ormar_config.pkname, None)
         self_fields = self.populate_default_values(self_fields)
         self.update_from_dict(
             {
@@ -88,18 +91,18 @@ class Model(ModelRow):
         )
 
         self_fields = self.translate_columns_to_aliases(self_fields)
-        expr = self.Meta.table.insert()
+        expr = self.ormar_config.table.insert()
         expr = expr.values(**self_fields)
 
-        pk = await self.Meta.database.execute(expr)
+        pk = await self.ormar_config.database.execute(expr)
         if pk and isinstance(pk, self.pk_type()):
-            setattr(self, self.Meta.pkname, pk)
+            setattr(self, self.ormar_config.pkname, pk)
 
         self.set_save_status(True)
         # refresh server side defaults
         if any(
             field.server_default is not None
-            for name, field in self.Meta.model_fields.items()
+            for name, field in self.ormar_config.model_fields.items()
             if name not in self_fields
         ):
             await self.load()
@@ -111,10 +114,10 @@ class Model(ModelRow):
         self,
         follow: bool = False,
         save_all: bool = False,
-        relation_map: Dict = None,
-        exclude: Union[Set, Dict] = None,
+        relation_map: Optional[Dict] = None,
+        exclude: Union[Set, Dict, None] = None,
         update_count: int = 0,
-        previous_model: "Model" = None,
+        previous_model: Optional["Model"] = None,
         relation_field: Optional["ForeignKeyField"] = None,
     ) -> int:
         """
@@ -210,7 +213,7 @@ class Model(ModelRow):
 
         return update_count
 
-    async def update(self: T, _columns: List[str] = None, **kwargs: Any) -> T:
+    async def update(self: T, _columns: Optional[List[str]] = None, **kwargs: Any) -> T:
         """
         Performs update of Model instance in the database.
         Fields can be updated before or you can pass them as kwargs.
@@ -240,14 +243,14 @@ class Model(ModelRow):
             sender=self.__class__, instance=self, passed_args=kwargs
         )
         self_fields = self._extract_model_db_fields()
-        self_fields.pop(self.get_column_name_from_alias(self.Meta.pkname))
+        self_fields.pop(self.get_column_name_from_alias(self.ormar_config.pkname))
         if _columns:
             self_fields = {k: v for k, v in self_fields.items() if k in _columns}
         self_fields = self.translate_columns_to_aliases(self_fields)
-        expr = self.Meta.table.update().values(**self_fields)
-        expr = expr.where(self.pk_column == getattr(self, self.Meta.pkname))
+        expr = self.ormar_config.table.update().values(**self_fields)
+        expr = expr.where(self.pk_column == getattr(self, self.ormar_config.pkname))
 
-        await self.Meta.database.execute(expr)
+        await self.ormar_config.database.execute(expr)
         self.set_save_status(True)
         await self.signals.post_update.send(sender=self.__class__, instance=self)
         return self
@@ -268,9 +271,9 @@ class Model(ModelRow):
         :rtype: int
         """
         await self.signals.pre_delete.send(sender=self.__class__, instance=self)
-        expr = self.Meta.table.delete()
-        expr = expr.where(self.pk_column == (getattr(self, self.Meta.pkname)))
-        result = await self.Meta.database.execute(expr)
+        expr = self.ormar_config.table.delete()
+        expr = expr.where(self.pk_column == (getattr(self, self.ormar_config.pkname)))
+        result = await self.ormar_config.database.execute(expr)
         self.set_save_status(False)
         await self.signals.post_delete.send(sender=self.__class__, instance=self)
         return result
@@ -286,8 +289,8 @@ class Model(ModelRow):
         :return: reloaded Model
         :rtype: Model
         """
-        expr = self.Meta.table.select().where(self.pk_column == self.pk)
-        row = await self.Meta.database.fetch_one(expr)
+        expr = self.ormar_config.table.select().where(self.pk_column == self.pk)
+        row = await self.ormar_config.database.fetch_one(expr)
         if not row:  # pragma nocover
             raise NoMatch("Instance was deleted from database and cannot be refreshed")
         kwargs = dict(row)
@@ -299,8 +302,8 @@ class Model(ModelRow):
     async def load_all(
         self: T,
         follow: bool = False,
-        exclude: Union[List, str, Set, Dict] = None,
-        order_by: Union[List, str] = None,
+        exclude: Union[List, str, Set, Dict, None] = None,
+        order_by: Union[List, str, None] = None,
     ) -> T:
         """
         Allow to refresh existing Models fields from database.
@@ -341,5 +344,5 @@ class Model(ModelRow):
             queryset = queryset.order_by(order_by)
         instance = await queryset.select_related(relations).get(pk=self.pk)
         self._orm.clear()
-        self.update_from_dict(instance.dict())
+        self.update_from_dict(instance.model_dump())
         return self
diff --git a/ormar/models/model_row.py b/ormar/models/model_row.py
index e3cf6ec..db0d2ce 100644
--- a/ormar/models/model_row.py
+++ b/ormar/models/model_row.py
@@ -1,4 +1,4 @@
-from typing import Any, Dict, List, Optional, TYPE_CHECKING, Tuple, Type, Union, cast
+from typing import TYPE_CHECKING, Any, Dict, List, Optional, Tuple, Type, Union, cast
 
 try:
     from sqlalchemy.engine.result import ResultProxy  # type: ignore
@@ -21,13 +21,13 @@ class ModelRow(NewBaseModel):
         cls,
         row: ResultProxy,
         source_model: Type["Model"],
-        select_related: List = None,
+        select_related: Optional[List] = None,
         related_models: Any = None,
-        related_field: "ForeignKeyField" = None,
-        excludable: ExcludableItems = None,
+        related_field: Optional["ForeignKeyField"] = None,
+        excludable: Optional[ExcludableItems] = None,
         current_relation_str: str = "",
         proxy_source_model: Optional[Type["Model"]] = None,
-        used_prefixes: List[str] = None,
+        used_prefixes: Optional[List[str]] = None,
     ) -> Optional["Model"]:
         """
         Model method to convert raw sql row from database into ormar.Model instance.
@@ -97,7 +97,7 @@ class ModelRow(NewBaseModel):
         )
 
         instance: Optional["Model"] = None
-        if item.get(cls.Meta.pkname, None) is not None:
+        if item.get(cls.ormar_config.pkname, None) is not None:
             item["__excluded__"] = cls.get_names_to_exclude(
                 excludable=excludable, alias=table_prefix
             )
@@ -130,11 +130,11 @@ class ModelRow(NewBaseModel):
             previous_model = related_field.through
         else:
             previous_model = related_field.owner
-        table_prefix = cls.Meta.alias_manager.resolve_relation_alias(
+        table_prefix = cls.ormar_config.alias_manager.resolve_relation_alias(
             from_model=previous_model, relation_name=related_field.name
         )
         if not table_prefix or table_prefix in used_prefixes:
-            manager = cls.Meta.alias_manager
+            manager = cls.ormar_config.alias_manager
             table_prefix = manager.resolve_relation_alias_after_complex(
                 source_model=source_model,
                 relation_str=current_relation_str,
@@ -153,8 +153,8 @@ class ModelRow(NewBaseModel):
         excludable: ExcludableItems,
         table_prefix: str,
         used_prefixes: List[str],
-        current_relation_str: str = None,
-        proxy_source_model: Type["Model"] = None,
+        current_relation_str: Optional[str] = None,
+        proxy_source_model: Optional[Type["Model"]] = None,
     ) -> dict:
         """
         Traverses structure of related models and populates the nested models
@@ -186,7 +186,7 @@ class ModelRow(NewBaseModel):
         """
 
         for related in related_models:
-            field = cls.Meta.model_fields[related]
+            field = cls.ormar_config.model_fields[related]
             field = cast("ForeignKeyField", field)
             model_cls = field.to
             model_excludable = excludable.get(
@@ -281,7 +281,7 @@ class ModelRow(NewBaseModel):
         :param proxy_source_model: source model from which querysetproxy is constructed
         :type proxy_source_model: Type["Model"]
         """
-        through_name = cls.Meta.model_fields[related].through.get_name()
+        through_name = cls.ormar_config.model_fields[related].through.get_name()
         through_child = cls._create_through_instance(
             row=row, related=related, through_name=through_name, excludable=excludable
         )
@@ -315,8 +315,8 @@ class ModelRow(NewBaseModel):
         :return: initialized through model without relation
         :rtype: "ModelRow"
         """
-        model_cls = cls.Meta.model_fields[through_name].to
-        table_prefix = cls.Meta.alias_manager.resolve_relation_alias(
+        model_cls = cls.ormar_config.model_fields[through_name].to
+        table_prefix = cls.ormar_config.alias_manager.resolve_relation_alias(
             from_model=cls, relation_name=related
         )
         # remove relations on through field
@@ -372,7 +372,7 @@ class ModelRow(NewBaseModel):
         )
 
         column_prefix = table_prefix + "_" if table_prefix else ""
-        for column in cls.Meta.table.columns:
+        for column in cls.ormar_config.table.columns:
             alias = cls.get_column_name_from_alias(column.name)
             if alias not in item and alias in selected_columns:
                 prefixed_name = f"{column_prefix}{column.name}"
diff --git a/ormar/models/newbasemodel.py b/ormar/models/newbasemodel.py
index 51182bd..77abe47 100644
--- a/ormar/models/newbasemodel.py
+++ b/ormar/models/newbasemodel.py
@@ -2,16 +2,16 @@ import base64
 import sys
 import warnings
 from typing import (
+    TYPE_CHECKING,
     AbstractSet,
     Any,
-    Callable,
     Dict,
     List,
+    Literal,
     Mapping,
     MutableSequence,
     Optional,
     Set,
-    TYPE_CHECKING,
     Tuple,
     Type,
     TypeVar,
@@ -19,33 +19,32 @@ from typing import (
     cast,
 )
 
-import databases
 import pydantic
 import sqlalchemy
-from pydantic import BaseModel
-
+import typing_extensions
 
 import ormar  # noqa I100
 from ormar.exceptions import ModelError, ModelPersistenceError
 from ormar.fields import BaseField
 from ormar.fields.foreign_key import ForeignKeyField
-from ormar.fields.parsers import encode_json
+from ormar.fields.parsers import decode_bytes, encode_json
 from ormar.models.helpers import register_relation_in_alias_manager
 from ormar.models.helpers.relations import expand_reverse_relationship
 from ormar.models.helpers.sqlalchemy import (
-    populate_meta_sqlalchemy_table_if_required,
+    populate_config_sqlalchemy_table_if_required,
     update_column_definition,
 )
-from ormar.models.metaclass import ModelMeta, ModelMetaclass
+from ormar.models.metaclass import ModelMetaclass
 from ormar.models.modelproxy import ModelTableProxy
 from ormar.models.utils import Extra
 from ormar.queryset.utils import translate_list_to_dict
 from ormar.relations.alias_manager import AliasManager
 from ormar.relations.relation import Relation
 from ormar.relations.relation_manager import RelationsManager
+from ormar.warnings import OrmarDeprecatedSince020
 
 if TYPE_CHECKING:  # pragma no cover
-    from ormar.models import Model
+    from ormar.models import Model, OrmarConfig
     from ormar.signals import SignalEmitter
 
     T = TypeVar("T", bound="NewBaseModel")
@@ -74,17 +73,12 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         "_pk_column",
         "__pk_only__",
         "__cached_hash__",
+        "__pydantic_extra__",
+        "__pydantic_fields_set__",
     )
 
     if TYPE_CHECKING:  # pragma no cover
         pk: Any
-        __model_fields__: Dict[str, BaseField]
-        __table__: sqlalchemy.Table
-        __pydantic_model__: Type[BaseModel]
-        __pkname__: str
-        __tablename__: str
-        __metadata__: sqlalchemy.MetaData
-        __database__: databases.Database
         __relation_map__: Optional[List[str]]
         __cached_hash__: Optional[int]
         _orm_relationship_manager: AliasManager
@@ -94,12 +88,10 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         _related_names: Optional[Set]
         _through_names: Optional[Set]
         _related_names_hash: str
-        _choices_fields: Set
-        _pydantic_fields: Set
         _quick_access_fields: Set
         _json_fields: Set
         _bytes_fields: Set
-        Meta: ModelMeta
+        ormar_config: OrmarConfig
 
     # noinspection PyMissingConstructor
     def __init__(self, *args: Any, **kwargs: Any) -> None:  # type: ignore
@@ -117,7 +109,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
 
         Json fields are automatically loaded/dumped if needed.
 
-        Models marked as abstract=True in internal Meta class cannot be initialized.
+        Models marked as abstract=True in internal OrmarConfig cannot be initialized.
 
         Accepts also special __pk_only__ flag that indicates that Model is constructed
         only with primary key value (so no other fields, it's a child model on other
@@ -144,31 +136,23 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         new_kwargs, through_tmp_dict = self._process_kwargs(kwargs)
 
         if not pk_only:
-            values, fields_set, validation_error = pydantic.validate_model(
-                self, new_kwargs  # type: ignore
+            self.__pydantic_validator__.validate_python(
+                new_kwargs, self_instance=self  # type: ignore
             )
-            if validation_error:
-                raise validation_error
         else:
-            fields_set = {self.Meta.pkname}
+            fields_set = {self.ormar_config.pkname}
             values = new_kwargs
-
-        object.__setattr__(self, "__dict__", values)
-        object.__setattr__(self, "__fields_set__", fields_set)
-
+            object.__setattr__(self, "__dict__", values)
+            object.__setattr__(self, "__pydantic_fields_set__", fields_set)
         # add back through fields
         new_kwargs.update(through_tmp_dict)
-        model_fields = object.__getattribute__(self, "Meta").model_fields
+        model_fields = object.__getattribute__(self, "ormar_config").model_fields
         # register the columns models after initialization
         for related in self.extract_related_names().union(self.extract_through_names()):
             model_fields[related].expand_relationship(
                 new_kwargs.get(related), self, to_register=True
             )
 
-        if hasattr(self, "_init_private_attributes"):
-            # introduced in pydantic 1.7
-            self._init_private_attributes()
-
     def __setattr__(self, name: str, value: Any) -> None:  # noqa CCR001
         """
         Overwrites setattr in pydantic parent as otherwise descriptors are not called.
@@ -189,7 +173,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
             super().__setattr__(name, value)
 
         # In this case, the hash could have changed, so update it
-        if name == self.Meta.pkname or self.pk is None:
+        if name == self.ormar_config.pkname or self.pk is None:
             object.__setattr__(self, "__cached_hash__", None)
             new_hash = hash(self)
 
@@ -198,20 +182,21 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
 
     def __getattr__(self, item: str) -> Any:
         """
-        Used only to silence mypy errors for Through models and reverse relations.
-        Not used in real life as in practice calls are intercepted
-        by RelationDescriptors
+        Used for private attributes of pydantic v2.
 
         :param item: name of attribute
         :type item: str
         :return: Any
         :rtype: Any
         """
-        return super().__getattribute__(item)
+        # TODO: Check __pydantic_extra__
+        if item == "__pydantic_extra__":
+            return None
+        return super().__getattr__(item)  # type: ignore
 
     def __getstate__(self) -> Dict[Any, Any]:
         state = super().__getstate__()
-        self_dict = self.dict()
+        self_dict = self.model_dump()
         state["__dict__"].update(**self_dict)
         return state
 
@@ -274,9 +259,9 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         :return: None
         :rtype: None
         """
-        if self.Meta.abstract:
+        if self.ormar_config.abstract:
             raise ModelError(f"You cannot initialize abstract model {self.get_name()}")
-        if self.Meta.requires_ref_update:
+        if self.ormar_config.requires_ref_update:
             raise ModelError(
                 f"Model {self.get_name()} has not updated "
                 f"ForwardRefs. \nBefore using the model you "
@@ -289,7 +274,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
 
         Removes property_fields
 
-        Checks if field is in the model fields or pydatnic fields.
+        Checks if field is in the model fields or pydantic fields.
 
         Nullifies fields that should be excluded.
 
@@ -300,9 +285,9 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         :return: modified kwargs
         :rtype: Tuple[Dict, Dict]
         """
-        property_fields = self.Meta.property_fields
-        model_fields = self.Meta.model_fields
-        pydantic_fields = set(self.__fields__.keys())
+        property_fields = self.ormar_config.property_fields
+        model_fields = self.ormar_config.model_fields
+        pydantic_fields = set(self.model_fields.keys())
 
         # remove property fields
         for prop_filed in property_fields:
@@ -310,7 +295,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
 
         excluded: Set[str] = kwargs.pop("__excluded__", set())
         if "pk" in kwargs:
-            kwargs[self.Meta.pkname] = kwargs.pop("pk")
+            kwargs[self.ormar_config.pkname] = kwargs.pop("pk")
 
         # extract through fields
         through_tmp_dict = dict()
@@ -326,9 +311,13 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
                     k,
                     self._convert_json(
                         k,
-                        model_fields[k].expand_relationship(v, self, to_register=False)
-                        if k in model_fields
-                        else (v if k in pydantic_fields else model_fields[k]),
+                        (
+                            model_fields[k].expand_relationship(
+                                v, self, to_register=False
+                            )
+                            if k in model_fields
+                            else (v if k in pydantic_fields else model_fields[k])
+                        ),
                     ),
                 )
                 for k, v in kwargs.items()
@@ -360,7 +349,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         :return: dict without extra fields
         :rtype: Dict
         """
-        if self.Meta.extra == Extra.ignore:
+        if self.ormar_config.extra == Extra.ignore:
             kwargs = {
                 k: v
                 for k, v in kwargs.items()
@@ -432,22 +421,6 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         else:
             return hash(self) == other.__hash__()
 
-    def _copy_and_set_values(
-        self: "NewBaseModel", values: "DictStrAny", fields_set: "SetStr", *, deep: bool
-    ) -> "NewBaseModel":
-        """
-        Overwrite related models values with dict representation to avoid infinite
-        recursion through related fields.
-        """
-        self_dict = values
-        self_dict.update(self.dict(exclude_list=True))
-        return cast(
-            "NewBaseModel",
-            super()._copy_and_set_values(
-                values=self_dict, fields_set=fields_set, deep=deep
-            ),
-        )
-
     @classmethod
     def get_name(cls, lower: bool = True) -> str:
         """
@@ -466,7 +439,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
     @property
     def pk_column(self) -> sqlalchemy.Column:
         """
-        Retrieves primary key sqlalchemy column from models Meta.table.
+        Retrieves primary key sqlalchemy column from models OrmarConfig.table.
         Each model has to have primary key.
         Only one primary key column is allowed.
 
@@ -475,7 +448,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         """
         if object.__getattribute__(self, "_pk_column") is not None:
             return object.__getattribute__(self, "_pk_column")
-        pk_columns = self.Meta.table.primary_key.columns.values()
+        pk_columns = self.ormar_config.table.primary_key.columns.values()
         pk_col = pk_columns[0]
         object.__setattr__(self, "_pk_column", pk_col)
         return pk_col
@@ -487,19 +460,19 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
 
     @property
     def signals(self) -> "SignalEmitter":
-        """Exposes signals from model Meta"""
-        return self.Meta.signals
+        """Exposes signals from model OrmarConfig"""
+        return self.ormar_config.signals
 
     @classmethod
     def pk_type(cls) -> Any:
         """Shortcut to models primary key field type"""
-        return cls.Meta.model_fields[cls.Meta.pkname].__type__
+        return cls.ormar_config.model_fields[cls.ormar_config.pkname].__type__
 
     @classmethod
     def db_backend_name(cls) -> str:
         """Shortcut to database dialect,
         cause some dialect require different treatment"""
-        return cls.Meta.database._backend._dialect.name
+        return cls.ormar_config.database._backend._dialect.name
 
     def remove(self, parent: "Model", name: str) -> None:
         """Removes child from relation with given name in RelationshipManager"""
@@ -509,32 +482,6 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         """Sets value of the save status"""
         object.__setattr__(self, "_orm_saved", status)
 
-    @classmethod
-    def get_properties(
-        cls, include: Union[Set, Dict, None], exclude: Union[Set, Dict, None]
-    ) -> Set[str]:
-        """
-        Returns a set of names of functions/fields decorated with
-        @property_field decorator.
-
-        They are added to dictionary when called directly and therefore also are
-        present in fastapi responses.
-
-        :param include: fields to include
-        :type include: Union[Set, Dict, None]
-        :param exclude: fields to exclude
-        :type exclude: Union[Set, Dict, None]
-        :return: set of property fields names
-        :rtype: Set[str]
-        """
-
-        props = cls.Meta.property_fields
-        if include:
-            props = {prop for prop in props if prop in include}
-        if exclude:
-            props = {prop for prop in props if prop not in exclude}
-        return props
-
     @classmethod
     def update_forward_refs(cls, **localns: Any) -> None:
         """
@@ -544,7 +491,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         Expands relationships, register relation in alias manager and substitutes
         sqlalchemy columns with new ones with proper column type (null before).
 
-        Populates Meta table of the Model which is left empty before.
+        Populates OrmarConfig table of the Model which is left empty before.
 
         Sets self_reference flag on models that links to themselves.
 
@@ -557,7 +504,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         """
         globalns = sys.modules[cls.__module__].__dict__.copy()
         globalns.setdefault(cls.__name__, cls)
-        fields_to_check = cls.Meta.model_fields.copy()
+        fields_to_check = cls.ormar_config.model_fields.copy()
         for field in fields_to_check.values():
             if field.has_unresolved_forward_refs():
                 field = cast(ForeignKeyField, field)
@@ -569,9 +516,10 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
                 expand_reverse_relationship(model_field=field)
                 register_relation_in_alias_manager(field=field)
                 update_column_definition(model=cls, field=field)
-        populate_meta_sqlalchemy_table_if_required(meta=cls.Meta)
-        super().update_forward_refs(**localns)
-        cls.Meta.requires_ref_update = False
+        populate_config_sqlalchemy_table_if_required(config=cls.ormar_config)
+        # super().update_forward_refs(**localns)
+        cls.model_rebuild(force=True)
+        cls.ormar_config.requires_ref_update = False
 
     @staticmethod
     def _get_not_excluded_fields(
@@ -626,26 +574,84 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         result = []
         for model in models:
             try:
-                result.append(
-                    model.dict(
-                        relation_map=relation_map,
+                model_dict = model.model_dump(
+                    relation_map=relation_map,
+                    include=include,
+                    exclude=exclude,
+                    exclude_primary_keys=exclude_primary_keys,
+                    exclude_through_models=exclude_through_models,
+                )
+                if not exclude_through_models:
+                    model.populate_through_models(
+                        model=model,
+                        model_dict=model_dict,
                         include=include,
                         exclude=exclude,
-                        exclude_primary_keys=exclude_primary_keys,
-                        exclude_through_models=exclude_through_models,
+                        relation_map=relation_map,
                     )
-                )
+                result.append(model_dict)
             except ReferenceError:  # pragma no cover
                 continue
         return result
 
+    @staticmethod
+    def populate_through_models(
+        model: "Model",
+        model_dict: Dict,
+        include: Union[Set, Dict],
+        exclude: Union[Set, Dict],
+        relation_map: Dict,
+    ) -> None:
+        """
+        Populates through models with values from dict representation.
+
+        :param model: model to populate through models
+        :type model: Model
+        :param model_dict: dict representation of the model
+        :type model_dict: Dict
+        :param include: fields to include
+        :type include: Dict
+        :param exclude: fields to exclude
+        :type exclude: Dict
+        :param relation_map: map of relations to follow to avoid circular refs
+        :type relation_map: Dict
+        :return: None
+        :rtype: None
+        """
+
+        include_dict = (
+            translate_list_to_dict(include)
+            if (include and isinstance(include, Set))
+            else include
+        )
+        exclude_dict = (
+            translate_list_to_dict(exclude)
+            if (exclude and isinstance(exclude, Set))
+            else exclude
+        )
+        models_to_populate = model._get_not_excluded_fields(
+            fields=model.extract_through_names(),
+            include=cast(Optional[Dict], include_dict),
+            exclude=cast(Optional[Dict], exclude_dict),
+        )
+        through_fields_to_populate = [
+            model.ormar_config.model_fields[through_model]
+            for through_model in models_to_populate
+            if model.ormar_config.model_fields[through_model].related_name
+            not in relation_map
+        ]
+        for through_field in through_fields_to_populate:
+            through_instance = getattr(model, through_field.name)
+            if through_instance:
+                model_dict[through_field.name] = through_instance.model_dump()
+
     @classmethod
     def _skip_ellipsis(
         cls, items: Union[Set, Dict, None], key: str, default_return: Any = None
     ) -> Union[Set, Dict, None]:
         """
         Helper to traverse the include/exclude dictionaries.
-        In dict() Ellipsis should be skipped as it indicates all fields required
+        In model_dump() Ellipsis should be skipped as it indicates all fields required
         and not the actual set/dict with fields names.
 
         :param items: current include/exclude value
@@ -722,8 +728,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
                         exclude_through_models=exclude_through_models,
                     )
                 elif nested_model is not None:
-
-                    dict_instance[field] = nested_model.dict(
+                    model_dict = nested_model.model_dump(
                         relation_map=self._skip_ellipsis(
                             relation_map, field, default_return=dict()
                         ),
@@ -732,26 +737,78 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
                         exclude_primary_keys=exclude_primary_keys,
                         exclude_through_models=exclude_through_models,
                     )
+                    if not exclude_through_models:
+                        nested_model.populate_through_models(
+                            model=nested_model,
+                            model_dict=model_dict,
+                            include=self._convert_all(
+                                self._skip_ellipsis(include, field)
+                            ),
+                            exclude=self._convert_all(
+                                self._skip_ellipsis(exclude, field)
+                            ),
+                            relation_map=self._skip_ellipsis(
+                                relation_map, field, default_return=dict()
+                            ),
+                        )
+                    dict_instance[field] = model_dict
                 else:
                     dict_instance[field] = None
-            except ReferenceError:
+            except ReferenceError:  # pragma: no cover
                 dict_instance[field] = None
         return dict_instance
 
+    @typing_extensions.deprecated(
+        "The `dict` method is deprecated; use `model_dump` instead.",
+        category=OrmarDeprecatedSince020,
+    )
     def dict(  # type: ignore # noqa A003
         self,
         *,
-        include: Union[Set, Dict] = None,
-        exclude: Union[Set, Dict] = None,
+        include: Union[Set, Dict, None] = None,
+        exclude: Union[Set, Dict, None] = None,
+        by_alias: bool = False,
+        exclude_unset: bool = False,
+        exclude_defaults: bool = False,
+        exclude_none: bool = False,
+        exclude_primary_keys: bool = False,
+        exclude_through_models: bool = False,
+        exclude_list: bool = False,
+        relation_map: Optional[Dict] = None,
+    ) -> "DictStrAny":  # noqa: A003 # pragma: no cover
+        warnings.warn(
+            "The `dict` method is deprecated; use `model_dump` instead.",
+            DeprecationWarning,
+        )
+        return self.model_dump(
+            include=include,
+            exclude=exclude,
+            by_alias=by_alias,
+            exclude_unset=exclude_unset,
+            exclude_defaults=exclude_defaults,
+            exclude_none=exclude_none,
+            exclude_primary_keys=exclude_primary_keys,
+            exclude_through_models=exclude_through_models,
+            exclude_list=exclude_list,
+            relation_map=relation_map,
+        )
+
+    def model_dump(  # type: ignore # noqa A003
+        self,
+        *,
+        mode: Union[Literal["json", "python"], str] = "python",
+        include: Union[Set, Dict, None] = None,
+        exclude: Union[Set, Dict, None] = None,
         by_alias: bool = False,
-        skip_defaults: bool = None,
         exclude_unset: bool = False,
         exclude_defaults: bool = False,
         exclude_none: bool = False,
         exclude_primary_keys: bool = False,
         exclude_through_models: bool = False,
         exclude_list: bool = False,
-        relation_map: Dict = None,
+        relation_map: Optional[Dict] = None,
+        round_trip: bool = False,
+        warnings: bool = True,
     ) -> "DictStrAny":  # noqa: A003'
         """
 
@@ -760,7 +817,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
 
         Nested models are also parsed to dictionaries.
 
-        Additionally fields decorated with @property_field are also added.
+        Additionally, fields decorated with @property_field are also added.
 
         :param exclude_through_models: flag to exclude through models from dict
         :type exclude_through_models: bool
@@ -772,8 +829,6 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         :type exclude: Union[Set, Dict, None]
         :param by_alias: flag to get values by alias - passed to pydantic
         :type by_alias: bool
-        :param skip_defaults: flag to not set values - passed to pydantic
-        :type skip_defaults: bool
         :param exclude_unset: flag to exclude not set values - passed to pydantic
         :type exclude_unset: bool
         :param exclude_defaults: flag to exclude default values - passed to pydantic
@@ -782,8 +837,16 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         :type exclude_none: bool
         :param exclude_list: flag to exclude lists of nested values models from dict
         :type exclude_list: bool
-        :param relation_map: map of the relations to follow to avoid circural deps
+        :param relation_map: map of the relations to follow to avoid circular deps
         :type relation_map: Dict
+        :param mode: The mode in which `to_python` should run.
+            If mode is 'json', the dictionary will only contain JSON serializable types.
+            If mode is 'python', the dictionary may contain any Python objects.
+        :type mode: str
+        :param round_trip: flag to enable serialization round-trip support
+        :type round_trip: bool
+        :param warnings: flag to log warnings for invalid fields
+        :type warnings: bool
         :return:
         :rtype:
         """
@@ -793,14 +856,16 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
             exclude_primary_keys=exclude_primary_keys,
             exclude_through_models=exclude_through_models,
         )
-        dict_instance = super().dict(
+        dict_instance = super().model_dump(
+            mode=mode,
             include=include,
             exclude=pydantic_exclude,
             by_alias=by_alias,
-            skip_defaults=skip_defaults,
-            exclude_unset=exclude_unset,
             exclude_defaults=exclude_defaults,
+            exclude_unset=exclude_unset,
             exclude_none=exclude_none,
+            round_trip=round_trip,
+            warnings=False,
         )
 
         dict_instance = {
@@ -808,10 +873,12 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
             for k, v in dict_instance.items()
         }
 
-        if include and isinstance(include, Set):
-            include = translate_list_to_dict(include)
-        if exclude and isinstance(exclude, Set):
-            exclude = translate_list_to_dict(exclude)
+        include_dict = (
+            translate_list_to_dict(include) if isinstance(include, Set) else include
+        )
+        exclude_dict = (
+            translate_list_to_dict(exclude) if isinstance(exclude, Set) else exclude
+        )
 
         relation_map = (
             relation_map
@@ -823,32 +890,57 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
             dict_instance = self._extract_nested_models(
                 relation_map=relation_map,
                 dict_instance=dict_instance,
-                include=include,  # type: ignore
-                exclude=exclude,  # type: ignore
+                include=include_dict,
+                exclude=exclude_dict,
                 exclude_primary_keys=exclude_primary_keys,
                 exclude_through_models=exclude_through_models,
                 exclude_list=exclude_list,
             )
 
-        # include model properties as fields in dict
-        if object.__getattribute__(self, "Meta").property_fields:
-            props = self.get_properties(include=include, exclude=exclude)
-            if props:
-                dict_instance.update({prop: getattr(self, prop) for prop in props})
-
         return dict_instance
 
+    @typing_extensions.deprecated(
+        "The `json` method is deprecated; use `model_dump_json` instead.",
+        category=OrmarDeprecatedSince020,
+    )
     def json(  # type: ignore # noqa A003
         self,
         *,
-        include: Union[Set, Dict] = None,
-        exclude: Union[Set, Dict] = None,
+        include: Union[Set, Dict, None] = None,
+        exclude: Union[Set, Dict, None] = None,
+        by_alias: bool = False,
+        exclude_unset: bool = False,
+        exclude_defaults: bool = False,
+        exclude_none: bool = False,
+        exclude_primary_keys: bool = False,
+        exclude_through_models: bool = False,
+        **dumps_kwargs: Any,
+    ) -> str:  # pragma: no cover
+        warnings.warn(
+            "The `json` method is deprecated; use `model_dump_json` instead.",
+            DeprecationWarning,
+        )
+        return self.model_dump_json(
+            include=include,
+            exclude=exclude,
+            by_alias=by_alias,
+            exclude_unset=exclude_unset,
+            exclude_defaults=exclude_defaults,
+            exclude_none=exclude_none,
+            exclude_primary_keys=exclude_primary_keys,
+            exclude_through_models=exclude_through_models,
+            **dumps_kwargs,
+        )
+
+    def model_dump_json(  # type: ignore # noqa A003
+        self,
+        *,
+        include: Union[Set, Dict, None] = None,
+        exclude: Union[Set, Dict, None] = None,
         by_alias: bool = False,
-        skip_defaults: bool = None,
         exclude_unset: bool = False,
         exclude_defaults: bool = False,
         exclude_none: bool = False,
-        encoder: Optional[Callable[[Any], Any]] = None,
         exclude_primary_keys: bool = False,
         exclude_through_models: bool = False,
         **dumps_kwargs: Any,
@@ -860,15 +952,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         `encoder` is an optional function to supply as `default` to json.dumps(),
         other arguments as per `json.dumps()`.
         """
-        if skip_defaults is not None:  # pragma: no cover
-            warnings.warn(
-                f'{self.__class__.__name__}.json(): "skip_defaults" is deprecated '
-                f'and replaced by "exclude_unset"',
-                DeprecationWarning,
-            )
-            exclude_unset = skip_defaults
-        encoder = cast(Callable[[Any], Any], encoder or self.__json_encoder__)
-        data = self.dict(
+        data = self.model_dump(
             include=include,
             exclude=exclude,
             by_alias=by_alias,
@@ -878,12 +962,24 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
             exclude_primary_keys=exclude_primary_keys,
             exclude_through_models=exclude_through_models,
         )
-        if self.__custom_root_type__:  # pragma: no cover
-            data = data["__root__"]
-        return self.__config__.json_dumps(data, default=encoder, **dumps_kwargs)
+        return self.__pydantic_serializer__.to_json(data, warnings=False).decode()
 
     @classmethod
+    @typing_extensions.deprecated(
+        "The `construct` method is deprecated; use `model_construct` instead.",
+        category=OrmarDeprecatedSince020,
+    )
     def construct(
+        cls: Type["T"], _fields_set: Union[Set[str], None] = None, **values: Any
+    ) -> "T":  # pragma: no cover
+        warnings.warn(
+            "The `construct` method is deprecated; use `model_construct` instead.",
+            DeprecationWarning,
+        )
+        return cls.model_construct(_fields_set=_fields_set, **values)
+
+    @classmethod
+    def model_construct(
         cls: Type["T"], _fields_set: Optional["SetStr"] = None, **values: Any
     ) -> "T":
         own_values = {
@@ -891,18 +987,52 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         }
         model = cls.__new__(cls)
         fields_values: Dict[str, Any] = {}
-        for name, field in cls.__fields__.items():
+        for name, field in cls.model_fields.items():
             if name in own_values:
                 fields_values[name] = own_values[name]
-            elif not field.required:
+            elif not field.is_required():
                 fields_values[name] = field.get_default()
         fields_values.update(own_values)
+
+        if _fields_set is None:
+            _fields_set = set(values.keys())
+
+        extra_allowed = cls.model_config.get("extra") == "allow"
+        if not extra_allowed:
+            fields_values.update(values)
         object.__setattr__(model, "__dict__", fields_values)
         model._initialize_internal_attributes()
         cls._construct_relations(model=model, values=values)
-        if _fields_set is None:
-            _fields_set = set(values.keys())
-        object.__setattr__(model, "__fields_set__", _fields_set)
+        object.__setattr__(model, "__pydantic_fields_set__", _fields_set)
+        return cls._pydantic_model_construct_finalizer(
+            model=model, extra_allowed=extra_allowed, values=values
+        )
+
+    @classmethod
+    def _pydantic_model_construct_finalizer(
+        cls: Type["T"], model: "T", extra_allowed: bool, **values: Any
+    ) -> "T":
+        """
+        Recreate pydantic model_construct logic here as we do not call super method.
+        """
+        _extra: Union[Dict[str, Any], None] = None
+        if extra_allowed:  # pragma: no cover
+            _extra = {}
+            for k, v in values.items():
+                _extra[k] = v
+
+        if not cls.__pydantic_root_model__:
+            object.__setattr__(model, "__pydantic_extra__", _extra)
+
+        if cls.__pydantic_post_init__:  # pragma: no cover
+            model.model_post_init(None)
+        elif not cls.__pydantic_root_model__:
+            # Note: if there are any private attributes,
+            # cls.__pydantic_post_init__ would exist
+            # Since it doesn't, that means that `__pydantic_private__`
+            # should be set to None
+            object.__setattr__(model, "__pydantic_private__", None)
+
         return model
 
     @classmethod
@@ -914,7 +1044,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
             value_to_set = values[relation]
             if not isinstance(value_to_set, list):
                 value_to_set = [value_to_set]
-            relation_field = cls.Meta.model_fields[relation]
+            relation_field = cls.ormar_config.model_fields[relation]
             relation_value = [
                 relation_field.expand_relationship(x, model, to_register=False)
                 for x in value_to_set
@@ -954,12 +1084,11 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         """
         if column_name not in self._bytes_fields:
             return value
-        field = self.Meta.model_fields[column_name]
-        if not isinstance(value, bytes) and value is not None:
-            if field.represent_as_base64_str:
-                value = base64.b64decode(value)
-            else:
-                value = value.encode("utf-8")
+        field = self.ormar_config.model_fields[column_name]
+        if value is not None:
+            value = decode_bytes(
+                value=value, represent_as_string=field.represent_as_base64_str
+            )
         return value
 
     def _convert_bytes_to_str(self, column_name: str, value: Any) -> Union[str, Dict]:
@@ -975,7 +1104,7 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         """
         if column_name not in self._bytes_fields:
             return value
-        field = self.Meta.model_fields[column_name]
+        field = self.ormar_config.model_fields[column_name]
         if (
             value is not None
             and not isinstance(value, str)
@@ -1021,16 +1150,15 @@ class NewBaseModel(pydantic.BaseModel, ModelTableProxy, metaclass=ModelMetaclass
         :return: dictionary of fields names and values.
         :rtype: Dict
         """
-        # TODO: Cache this dictionary?
         self_fields = self._extract_own_model_fields()
         self_fields = {
             k: v
             for k, v in self_fields.items()
-            if self.get_column_alias(k) in self.Meta.table.columns
+            if self.get_column_alias(k) in self.ormar_config.table.columns
         }
         for field in self._extract_db_related_names():
-            relation_field = self.Meta.model_fields[field]
-            target_pk_name = relation_field.to.Meta.pkname
+            relation_field = self.ormar_config.model_fields[field]
+            target_pk_name = relation_field.to.ormar_config.pkname
             target_field = getattr(self, field)
             self_fields[field] = getattr(target_field, target_pk_name, None)
             if not relation_field.nullable and not self_fields[field]:
diff --git a/ormar/models/ormar_config.py b/ormar/models/ormar_config.py
new file mode 100644
index 0000000..e4941b1
--- /dev/null
+++ b/ormar/models/ormar_config.py
@@ -0,0 +1,85 @@
+from typing import TYPE_CHECKING, Dict, List, Optional, Set, Type, Union
+
+import databases
+import sqlalchemy
+from sqlalchemy.sql.schema import ColumnCollectionConstraint
+
+from ormar.fields import BaseField, ForeignKeyField, ManyToManyField
+from ormar.models.helpers import alias_manager
+from ormar.models.utils import Extra
+from ormar.queryset.queryset import QuerySet
+from ormar.relations import AliasManager
+from ormar.signals import SignalEmitter
+
+
+class OrmarConfig:
+
+    if TYPE_CHECKING:  # pragma: no cover
+        pkname: str
+        metadata: sqlalchemy.MetaData
+        database: databases.Database
+        tablename: str
+        order_by: List[str]
+        abstract: bool
+        exclude_parent_fields: List[str]
+        constraints: List[ColumnCollectionConstraint]
+
+    def __init__(
+        self,
+        metadata: Optional[sqlalchemy.MetaData] = None,
+        database: Optional[databases.Database] = None,
+        engine: Optional[sqlalchemy.engine.Engine] = None,
+        tablename: Optional[str] = None,
+        order_by: Optional[List[str]] = None,
+        abstract: bool = False,
+        exclude_parent_fields: Optional[List[str]] = None,
+        queryset_class: Type[QuerySet] = QuerySet,
+        extra: Extra = Extra.forbid,
+        constraints: Optional[List[ColumnCollectionConstraint]] = None,
+    ) -> None:
+        self.pkname = None  # type: ignore
+        self.metadata = metadata
+        self.database = database  # type: ignore
+        self.engine = engine  # type: ignore
+        self.tablename = tablename  # type: ignore
+        self.orders_by = order_by or []
+        self.columns: List[sqlalchemy.Column] = []
+        self.constraints = constraints or []
+        self.model_fields: Dict[
+            str, Union[BaseField, ForeignKeyField, ManyToManyField]
+        ] = {}
+        self.alias_manager: AliasManager = alias_manager
+        self.property_fields: Set = set()
+        self.signals: SignalEmitter = SignalEmitter()
+        self.abstract = abstract
+        self.requires_ref_update: bool = False
+        self.exclude_parent_fields = exclude_parent_fields or []
+        self.extra = extra
+        self.queryset_class = queryset_class
+        self.table: sqlalchemy.Table = None
+
+    def copy(
+        self,
+        metadata: Optional[sqlalchemy.MetaData] = None,
+        database: Optional[databases.Database] = None,
+        engine: Optional[sqlalchemy.engine.Engine] = None,
+        tablename: Optional[str] = None,
+        order_by: Optional[List[str]] = None,
+        abstract: Optional[bool] = None,
+        exclude_parent_fields: Optional[List[str]] = None,
+        queryset_class: Optional[Type[QuerySet]] = None,
+        extra: Optional[Extra] = None,
+        constraints: Optional[List[ColumnCollectionConstraint]] = None,
+    ) -> "OrmarConfig":
+        return OrmarConfig(
+            metadata=metadata or self.metadata,
+            database=database or self.database,
+            engine=engine or self.engine,
+            tablename=tablename,
+            order_by=order_by,
+            abstract=abstract or self.abstract,
+            exclude_parent_fields=exclude_parent_fields,
+            queryset_class=queryset_class or self.queryset_class,
+            extra=extra or self.extra,
+            constraints=constraints,
+        )
diff --git a/ormar/models/quick_access_views.py b/ormar/models/quick_access_views.py
index a822375..17cadb7 100644
--- a/ormar/models/quick_access_views.py
+++ b/ormar/models/quick_access_views.py
@@ -2,14 +2,17 @@
 Contains set of fields/methods etc names that are used to bypass the checks in
 NewBaseModel __getattribute__ calls to speed the calls.
 """
+
 quick_access_set = {
     "Config",
-    "Meta",
+    "model_config",
+    "model_fields",
+    "__cached_hash__",
     "__class__",
     "__config__",
     "__custom_root_type__",
     "__dict__",
-    "__fields__",
+    "model_fields",
     "__fields_set__",
     "__json_encoder__",
     "__pk_only__",
@@ -18,7 +21,6 @@ quick_access_set = {
     "__private_attributes__",
     "__same__",
     "_calculate_keys",
-    "_choices_fields",
     "_convert_json",
     "_extract_db_related_names",
     "_extract_model_db_fields",
diff --git a/ormar/models/traversible.py b/ormar/models/traversible.py
index 3a90bb9..0bb3237 100644
--- a/ormar/models/traversible.py
+++ b/ormar/models/traversible.py
@@ -1,4 +1,4 @@
-from typing import Any, List, Optional, TYPE_CHECKING, Type
+from typing import TYPE_CHECKING, Any, List, Optional, Type
 
 if TYPE_CHECKING:  # pragma no cover
     from ormar.models.mixins.relation_mixin import RelationMixin
@@ -18,8 +18,8 @@ class NodeList:
     def add(
         self,
         node_class: Type["RelationMixin"],
-        relation_name: str = None,
-        parent_node: "Node" = None,
+        relation_name: Optional[str] = None,
+        parent_node: Optional["Node"] = None,
     ) -> "Node":
         """
         Adds new Node or returns the existing one
@@ -50,7 +50,7 @@ class NodeList:
         self,
         node_class: Type["RelationMixin"],
         relation_name: Optional[str] = None,
-        parent_node: "Node" = None,
+        parent_node: Optional["Node"] = None,
     ) -> Optional["Node"]:
         """
         Searches for existing node with given parameters
@@ -78,8 +78,8 @@ class Node:
     def __init__(
         self,
         node_class: Type["RelationMixin"],
-        relation_name: str = None,
-        parent_node: "Node" = None,
+        relation_name: Optional[str] = None,
+        parent_node: Optional["Node"] = None,
     ) -> None:
         self.relation_name = relation_name
         self.node_class = node_class
@@ -108,7 +108,7 @@ class Node:
         :return: result of the check
         :rtype: bool
         """
-        target_model = self.node_class.Meta.model_fields[relation_name].to
+        target_model = self.node_class.ormar_config.model_fields[relation_name].to
         if self.parent_node:
             node = self
             while node.parent_node:
diff --git a/ormar/protocols/queryset_protocol.py b/ormar/protocols/queryset_protocol.py
index a2c1d58..fb8bcb9 100644
--- a/ormar/protocols/queryset_protocol.py
+++ b/ormar/protocols/queryset_protocol.py
@@ -1,4 +1,4 @@
-from typing import Any, Dict, List, Optional, Sequence, Set, TYPE_CHECKING, Tuple, Union
+from typing import TYPE_CHECKING, Any, Dict, List, Optional, Sequence, Set, Tuple, Union
 
 try:
     from typing import Protocol
@@ -17,59 +17,44 @@ class QuerySetProtocol(Protocol):  # pragma: nocover
     def exclude(self, **kwargs: Any) -> "QuerysetProxy":  # noqa: A003, A001
         ...
 
-    def select_related(self, related: Union[List, str]) -> "QuerysetProxy":
-        ...
+    def select_related(self, related: Union[List, str]) -> "QuerysetProxy": ...
 
-    def prefetch_related(self, related: Union[List, str]) -> "QuerysetProxy":
-        ...
+    def prefetch_related(self, related: Union[List, str]) -> "QuerysetProxy": ...
 
-    async def exists(self) -> bool:
-        ...
+    async def exists(self) -> bool: ...
 
-    async def count(self, distinct: bool = True) -> int:
-        ...
+    async def count(self, distinct: bool = True) -> int: ...
 
-    async def clear(self) -> int:
-        ...
+    async def clear(self) -> int: ...
 
-    def limit(self, limit_count: int) -> "QuerysetProxy":
-        ...
+    def limit(self, limit_count: int) -> "QuerysetProxy": ...
 
-    def offset(self, offset: int) -> "QuerysetProxy":
-        ...
+    def offset(self, offset: int) -> "QuerysetProxy": ...
 
-    async def first(self, **kwargs: Any) -> "Model":
-        ...
+    async def first(self, **kwargs: Any) -> "Model": ...
 
-    async def get(self, **kwargs: Any) -> "Model":
-        ...
+    async def get(self, **kwargs: Any) -> "Model": ...
 
     async def all(  # noqa: A003, A001
         self, **kwargs: Any
-    ) -> Sequence[Optional["Model"]]:
-        ...
+    ) -> Sequence[Optional["Model"]]: ...
 
-    async def create(self, **kwargs: Any) -> "Model":
-        ...
+    async def create(self, **kwargs: Any) -> "Model": ...
 
-    async def update(self, each: bool = False, **kwargs: Any) -> int:
-        ...
+    async def update(self, each: bool = False, **kwargs: Any) -> int: ...
 
     async def get_or_create(
         self,
         _defaults: Optional[Dict[str, Any]] = None,
         **kwargs: Any,
-    ) -> Tuple["Model", bool]:
-        ...
+    ) -> Tuple["Model", bool]: ...
 
-    async def update_or_create(self, **kwargs: Any) -> "Model":
-        ...
+    async def update_or_create(self, **kwargs: Any) -> "Model": ...
 
-    def fields(self, columns: Union[List, str, Set, Dict]) -> "QuerysetProxy":
-        ...
+    def fields(self, columns: Union[List, str, Set, Dict]) -> "QuerysetProxy": ...
 
-    def exclude_fields(self, columns: Union[List, str, Set, Dict]) -> "QuerysetProxy":
-        ...
+    def exclude_fields(
+        self, columns: Union[List, str, Set, Dict]
+    ) -> "QuerysetProxy": ...
 
-    def order_by(self, columns: Union[List, str]) -> "QuerysetProxy":
-        ...
+    def order_by(self, columns: Union[List, str]) -> "QuerysetProxy": ...
diff --git a/ormar/protocols/relation_protocol.py b/ormar/protocols/relation_protocol.py
index b551b8d..4c44bca 100644
--- a/ormar/protocols/relation_protocol.py
+++ b/ormar/protocols/relation_protocol.py
@@ -10,8 +10,6 @@ if TYPE_CHECKING:  # pragma: nocover
 
 
 class RelationProtocol(Protocol):  # pragma: nocover
-    def add(self, child: "Model") -> None:
-        ...
+    def add(self, child: "Model") -> None: ...
 
-    def remove(self, child: Union["Model", Type["Model"]]) -> None:
-        ...
+    def remove(self, child: Union["Model", Type["Model"]]) -> None: ...
diff --git a/ormar/queryset/__init__.py b/ormar/queryset/__init__.py
index 32fbee4..02e4eec 100644
--- a/ormar/queryset/__init__.py
+++ b/ormar/queryset/__init__.py
@@ -1,13 +1,11 @@
 """
 Contains QuerySet and different Query classes to allow for constructing of sql queries.
 """
+
 from ormar.queryset.actions import FilterAction, OrderAction, SelectAction
 from ormar.queryset.clause import and_, or_
 from ormar.queryset.field_accessor import FieldAccessor
-from ormar.queryset.queries import FilterQuery
-from ormar.queryset.queries import LimitQuery
-from ormar.queryset.queries import OffsetQuery
-from ormar.queryset.queries import OrderQuery
+from ormar.queryset.queries import FilterQuery, LimitQuery, OffsetQuery, OrderQuery
 from ormar.queryset.queryset import QuerySet
 
 __all__ = [
diff --git a/ormar/queryset/actions/filter_action.py b/ormar/queryset/actions/filter_action.py
index e393333..f5ab832 100644
--- a/ormar/queryset/actions/filter_action.py
+++ b/ormar/queryset/actions/filter_action.py
@@ -1,4 +1,4 @@
-from typing import Any, TYPE_CHECKING, Type
+from typing import TYPE_CHECKING, Any, Type
 
 import sqlalchemy
 
@@ -143,8 +143,10 @@ class FilterAction(QueryAction):
         else:
             filter_value = self.filter_value
         if self.table_prefix:
-            aliased_table = self.source_model.Meta.alias_manager.prefixed_table_name(
-                self.table_prefix, self.column.table
+            aliased_table = (
+                self.source_model.ormar_config.alias_manager.prefixed_table_name(
+                    self.table_prefix, self.column.table
+                )
             )
             aliased_column = getattr(aliased_table.c, self.column.name)
         else:
diff --git a/ormar/queryset/actions/order_action.py b/ormar/queryset/actions/order_action.py
index 05114bf..a77563c 100644
--- a/ormar/queryset/actions/order_action.py
+++ b/ormar/queryset/actions/order_action.py
@@ -1,4 +1,4 @@
-from typing import TYPE_CHECKING, Type
+from typing import TYPE_CHECKING, Optional, Type
 
 import sqlalchemy
 from sqlalchemy import text
@@ -20,7 +20,7 @@ class OrderAction(QueryAction):
     """
 
     def __init__(
-        self, order_str: str, model_cls: Type["Model"], alias: str = None
+        self, order_str: str, model_cls: Type["Model"], alias: Optional[str] = None
     ) -> None:
         self.direction: str = ""
         super().__init__(query_str=order_str, model_cls=model_cls)
@@ -36,8 +36,10 @@ class OrderAction(QueryAction):
 
     @property
     def is_postgres_bool(self) -> bool:
-        dialect = self.target_model.Meta.database._backend._dialect.name
-        field_type = self.target_model.Meta.model_fields[self.field_name].__type__
+        dialect = self.target_model.ormar_config.database._backend._dialect.name
+        field_type = self.target_model.ormar_config.model_fields[
+            self.field_name
+        ].__type__
         return dialect == "postgresql" and field_type == bool
 
     def get_field_name_text(self) -> str:
@@ -78,7 +80,7 @@ class OrderAction(QueryAction):
         :return: complied and escaped clause
         :rtype: sqlalchemy.sql.elements.TextClause
         """
-        dialect = self.target_model.Meta.database._backend._dialect
+        dialect = self.target_model.ormar_config.database._backend._dialect
         quoter = dialect.identifier_preparer.quote
         prefix = f"{self.table_prefix}_" if self.table_prefix else ""
         table_name = self.table.name
diff --git a/ormar/queryset/actions/query_action.py b/ormar/queryset/actions/query_action.py
index 2c6ee84..b8bd651 100644
--- a/ormar/queryset/actions/query_action.py
+++ b/ormar/queryset/actions/query_action.py
@@ -1,5 +1,5 @@
 import abc
-from typing import Any, List, TYPE_CHECKING, Type
+from typing import TYPE_CHECKING, Any, List, Type
 
 import sqlalchemy
 
@@ -54,13 +54,13 @@ class QueryAction(abc.ABC):
     @property
     def table(self) -> sqlalchemy.Table:
         """Shortcut to sqlalchemy Table of filtered target model"""
-        return self.target_model.Meta.table
+        return self.target_model.ormar_config.table
 
     @property
     def column(self) -> sqlalchemy.Column:
         """Shortcut to sqlalchemy column of filtered target model"""
         aliased_name = self.target_model.get_column_alias(self.field_name)
-        return self.target_model.Meta.table.columns[aliased_name]
+        return self.target_model.ormar_config.table.columns[aliased_name]
 
     def update_select_related(self, select_related: List[str]) -> List[str]:
         """
diff --git a/ormar/queryset/actions/select_action.py b/ormar/queryset/actions/select_action.py
index 92e5991..141b095 100644
--- a/ormar/queryset/actions/select_action.py
+++ b/ormar/queryset/actions/select_action.py
@@ -1,5 +1,5 @@
 import decimal
-from typing import Any, Callable, TYPE_CHECKING, Type
+from typing import TYPE_CHECKING, Any, Callable, Optional, Type
 
 import sqlalchemy
 
@@ -20,7 +20,7 @@ class SelectAction(QueryAction):
     """
 
     def __init__(
-        self, select_str: str, model_cls: Type["Model"], alias: str = None
+        self, select_str: str, model_cls: Type["Model"], alias: Optional[str] = None
     ) -> None:
         super().__init__(query_str=select_str, model_cls=model_cls)
         if alias:  # pragma: no cover
@@ -36,7 +36,7 @@ class SelectAction(QueryAction):
         return self.get_target_field_type() in [int, float, decimal.Decimal]
 
     def get_target_field_type(self) -> Any:
-        return self.target_model.Meta.model_fields[self.field_name].__type__
+        return self.target_model.ormar_config.model_fields[self.field_name].__type__
 
     def get_text_clause(self) -> sqlalchemy.sql.expression.TextClause:
         alias = f"{self.table_prefix}_" if self.table_prefix else ""
diff --git a/ormar/queryset/clause.py b/ormar/queryset/clause.py
index 2a86d45..0000ac1 100644
--- a/ormar/queryset/clause.py
+++ b/ormar/queryset/clause.py
@@ -1,7 +1,7 @@
 import itertools
 from dataclasses import dataclass
 from enum import Enum
-from typing import Any, Generator, List, TYPE_CHECKING, Tuple, Type
+from typing import TYPE_CHECKING, Any, Generator, List, Optional, Tuple, Type
 
 import sqlalchemy
 
@@ -52,8 +52,8 @@ class FilterGroup:
     def resolve(
         self,
         model_cls: Type["Model"],
-        select_related: List = None,
-        filter_clauses: List = None,
+        select_related: Optional[List] = None,
+        filter_clauses: Optional[List] = None,
     ) -> Tuple[List[FilterAction], List[str]]:
         """
         Resolves the FilterGroups actions to use proper target model, replace
@@ -180,12 +180,11 @@ class QueryClause:
     def __init__(
         self, model_cls: Type["Model"], filter_clauses: List, select_related: List
     ) -> None:
-
         self._select_related = select_related[:]
         self.filter_clauses = filter_clauses[:]
 
         self.model_cls = model_cls
-        self.table = self.model_cls.Meta.table
+        self.table = self.model_cls.ormar_config.table
 
     def prepare_filter(  # noqa: A003
         self, _own_only: bool = False, **kwargs: Any
@@ -203,7 +202,9 @@ class QueryClause:
         :rtype: Tuple[List[sqlalchemy.sql.elements.TextClause], List[str]]
         """
         if kwargs.get("pk"):
-            pk_name = self.model_cls.get_column_alias(self.model_cls.Meta.pkname)
+            pk_name = self.model_cls.get_column_alias(
+                self.model_cls.ormar_config.pkname
+            )
             kwargs[pk_name] = kwargs.pop("pk")
 
         filter_clauses, select_related = self._populate_filter_clauses(
@@ -262,7 +263,7 @@ class QueryClause:
         """
         prefixes = self._parse_related_prefixes(select_related=select_related)
 
-        manager = self.model_cls.Meta.alias_manager
+        manager = self.model_cls.ormar_config.alias_manager
         filtered_prefixes = sorted(prefixes, key=lambda x: x.table_prefix)
         grouped = itertools.groupby(filtered_prefixes, key=lambda x: x.table_prefix)
         for _, group in grouped:
@@ -320,7 +321,7 @@ class QueryClause:
         :param action: action to switch prefix in
         :type action: ormar.queryset.actions.filter_action.FilterAction
         """
-        manager = self.model_cls.Meta.alias_manager
+        manager = self.model_cls.ormar_config.alias_manager
         new_alias = manager.resolve_relation_alias(self.model_cls, action.related_str)
         if "__" in action.related_str and new_alias:
             action.table_prefix = new_alias
diff --git a/ormar/queryset/field_accessor.py b/ormar/queryset/field_accessor.py
index b274837..3b66905 100644
--- a/ormar/queryset/field_accessor.py
+++ b/ormar/queryset/field_accessor.py
@@ -1,4 +1,4 @@
-from typing import Any, TYPE_CHECKING, Type, cast
+from typing import TYPE_CHECKING, Any, Optional, Type, cast
 
 from ormar.queryset.actions import OrderAction
 from ormar.queryset.actions.filter_action import METHODS_TO_OPERATORS
@@ -17,8 +17,8 @@ class FieldAccessor:
     def __init__(
         self,
         source_model: Type["Model"],
-        field: "BaseField" = None,
-        model: Type["Model"] = None,
+        field: Optional["BaseField"] = None,
+        model: Optional[Type["Model"]] = None,
         access_chain: str = "",
     ) -> None:
         self._source_model = source_model
@@ -26,15 +26,6 @@ class FieldAccessor:
         self._model = model
         self._access_chain = access_chain
 
-    def __bool__(self) -> bool:
-        """
-        Hack to avoid pydantic name check from parent model, returns false
-
-        :return: False
-        :rtype: bool
-        """
-        return False
-
     def __getattr__(self, item: str) -> Any:
         """
         Accessor return new accessor for each field and nested models.
@@ -53,9 +44,10 @@ class FieldAccessor:
 
         if (
             object.__getattribute__(self, "_model")
-            and item in object.__getattribute__(self, "_model").Meta.model_fields
+            and item
+            in object.__getattribute__(self, "_model").ormar_config.model_fields
         ):
-            field = cast("Model", self._model).Meta.model_fields[item]
+            field = cast("Model", self._model).ormar_config.model_fields[item]
             if field.is_relation:
                 return FieldAccessor(
                     source_model=self._source_model,
diff --git a/ormar/queryset/join.py b/ormar/queryset/join.py
index 29d0614..9d7e4d1 100644
--- a/ormar/queryset/join.py
+++ b/ormar/queryset/join.py
@@ -1,4 +1,4 @@
-from typing import Any, Dict, List, Optional, TYPE_CHECKING, Tuple, Type, cast
+from typing import TYPE_CHECKING, Any, Dict, List, Optional, Tuple, Type, cast
 
 import sqlalchemy
 from sqlalchemy import text
@@ -8,9 +8,9 @@ from ormar.exceptions import ModelDefinitionError, RelationshipInstanceError
 from ormar.relations import AliasManager
 
 if TYPE_CHECKING:  # pragma no cover
-    from ormar import Model, ManyToManyField
-    from ormar.queryset import OrderAction
+    from ormar import ManyToManyField, Model
     from ormar.models.excludable import ExcludableItems
+    from ormar.queryset import OrderAction
 
 
 class SqlJoin:
@@ -27,8 +27,8 @@ class SqlJoin:
         relation_str: str,
         related_models: Any = None,
         own_alias: str = "",
-        source_model: Type["Model"] = None,
-        already_sorted: Dict = None,
+        source_model: Optional[Type["Model"]] = None,
+        already_sorted: Optional[Dict] = None,
     ) -> None:
         self.relation_name = relation_name
         self.related_models = related_models or []
@@ -43,7 +43,9 @@ class SqlJoin:
         self.main_model = main_model
         self.own_alias = own_alias
         self.used_aliases = used_aliases
-        self.target_field = self.main_model.Meta.model_fields[self.relation_name]
+        self.target_field = self.main_model.ormar_config.model_fields[
+            self.relation_name
+        ]
 
         self._next_model: Optional[Type["Model"]] = None
         self._next_alias: Optional[str] = None
@@ -76,12 +78,12 @@ class SqlJoin:
     @property
     def alias_manager(self) -> AliasManager:
         """
-        Shortcut for ormar's model AliasManager stored on Meta.
+        Shortcut for ormar's model AliasManager stored on OrmarConfig.
 
-        :return: alias manager from model's Meta
+        :return: alias manager from model's OrmarConfig
         :rtype: AliasManager
         """
-        return self.main_model.Meta.alias_manager
+        return self.main_model.ormar_config.alias_manager
 
     @property
     def to_table(self) -> sqlalchemy.Table:
@@ -90,9 +92,16 @@ class SqlJoin:
         :return: name of the target table
         :rtype: str
         """
-        return self.next_model.Meta.table
+        return self.next_model.ormar_config.table
 
-    def _on_clause(self, previous_alias: str, from_table_name:str, from_column_name: str, to_table_name: str, to_column_name: str) -> text:
+    def _on_clause(
+        self,
+        previous_alias: str,
+        from_table_name: str,
+        from_column_name: str,
+        to_table_name: str,
+        to_column_name: str,
+    ) -> text:
         """
         Receives aliases and names of both ends of the join and combines them
         into one text clause used in joins.
@@ -110,13 +119,17 @@ class SqlJoin:
         :return: clause combining all strings
         :rtype: sqlalchemy.text
         """
-        dialect = self.main_model.Meta.database._backend._dialect
+        dialect = self.main_model.ormar_config.database._backend._dialect
         quoter = dialect.identifier_preparer.quote
-        left_part = f"{quoter(f'{self.next_alias}_{to_table_name}')}.{quoter(to_column_name)}"
+        left_part = (
+            f"{quoter(f'{self.next_alias}_{to_table_name}')}.{quoter(to_column_name)}"
+        )
         if not previous_alias:
             right_part = f"{quoter(from_table_name)}.{quoter(from_column_name)}"
         else:
-            right_part = f"{quoter(f'{previous_alias}_{from_table_name}')}.{from_column_name}"
+            right_part = (
+                f"{quoter(f'{previous_alias}_{from_table_name}')}.{from_column_name}"
+            )
 
         return text(f"{left_part}={right_part}")
 
@@ -235,7 +248,9 @@ class SqlJoin:
 
         self.relation_name = new_part
         self.own_alias = self.next_alias
-        self.target_field = self.next_model.Meta.model_fields[self.relation_name]
+        self.target_field = self.next_model.ormar_config.model_fields[
+            self.relation_name
+        ]
 
     def _process_m2m_related_name_change(self, reverse: bool = False) -> str:
         """
@@ -281,7 +296,7 @@ class SqlJoin:
 
         on_clause = self._on_clause(
             previous_alias=self.own_alias,
-            from_table_name=self.target_field.owner.Meta.tablename,
+            from_table_name=self.target_field.owner.ormar_config.tablename,
             from_column_name=from_key,
             to_table_name=self.to_table.name,
             to_column_name=to_key,
@@ -309,7 +324,7 @@ class SqlJoin:
         self.used_aliases.append(self.next_alias)
 
     def _set_default_primary_key_order_by(self) -> None:
-        for order_by in self.next_model.Meta.orders_by:
+        for order_by in self.next_model.ormar_config.orders_by:
             clause = ormar.OrderAction(
                 order_str=order_by, model_cls=self.next_model, alias=self.next_alias
             )
@@ -399,16 +414,20 @@ class SqlJoin:
         """
         if self.target_field.is_multi:
             to_key = self._process_m2m_related_name_change(reverse=True)
-            from_key = self.main_model.get_column_alias(self.main_model.Meta.pkname)
+            from_key = self.main_model.get_column_alias(
+                self.main_model.ormar_config.pkname
+            )
 
         elif self.target_field.virtual:
             to_field = self.target_field.get_related_name()
             to_key = self.target_field.to.get_column_alias(to_field)
-            from_key = self.main_model.get_column_alias(self.main_model.Meta.pkname)
+            from_key = self.main_model.get_column_alias(
+                self.main_model.ormar_config.pkname
+            )
 
         else:
             to_key = self.target_field.to.get_column_alias(
-                self.target_field.to.Meta.pkname
+                self.target_field.to.ormar_config.pkname
             )
             from_key = self.main_model.get_column_alias(self.relation_name)
 
diff --git a/ormar/queryset/queries/filter_query.py b/ormar/queryset/queries/filter_query.py
index cb9b880..e6b7e82 100644
--- a/ormar/queryset/queries/filter_query.py
+++ b/ormar/queryset/queries/filter_query.py
@@ -1,6 +1,7 @@
 from typing import List
 
 import sqlalchemy
+
 from ormar.queryset.actions.filter_action import FilterAction
 
 
diff --git a/ormar/queryset/queries/prefetch_query.py b/ormar/queryset/queries/prefetch_query.py
index d30b9d7..66c2e47 100644
--- a/ormar/queryset/queries/prefetch_query.py
+++ b/ormar/queryset/queries/prefetch_query.py
@@ -1,4 +1,4 @@
-from typing import Dict, List, Sequence, Set, TYPE_CHECKING, Tuple, Type, cast
+from typing import TYPE_CHECKING, Dict, List, Sequence, Set, Tuple, Type, cast
 
 import ormar
 from ormar.queryset.clause import QueryClause
@@ -7,9 +7,9 @@ from ormar.queryset.utils import extract_models_to_dict_of_lists, translate_list
 
 if TYPE_CHECKING:  # pragma: no cover
     from ormar import Model
-    from ormar.fields import ForeignKeyField, BaseField
-    from ormar.queryset import OrderAction
+    from ormar.fields import BaseField, ForeignKeyField
     from ormar.models.excludable import ExcludableItems
+    from ormar.queryset import OrderAction
 
 
 def sort_models(models: List["Model"], orders_by: Dict) -> List["Model"]:
@@ -96,9 +96,8 @@ class PrefetchQuery:
         select_related: List,
         orders_by: List["OrderAction"],
     ) -> None:
-
         self.model = model_cls
-        self.database = self.model.Meta.database
+        self.database = self.model.ormar_config.database
         self._prefetch_related = prefetch_related
         self._select_related = select_related
         self.excludable = excludable
@@ -279,7 +278,7 @@ class PrefetchQuery:
         )
 
         for related in related_to_extract:
-            target_field = model.Meta.model_fields[related]
+            target_field = model.ormar_config.model_fields[related]
             target_field = cast("ForeignKeyField", target_field)
             target_model = target_field.to.get_name()
             model_id = model.get_relation_model_id(target_field=target_field)
@@ -381,7 +380,7 @@ class PrefetchQuery:
         :return: None
         :rtype: None
         """
-        target_field = target_model.Meta.model_fields[related]
+        target_field = target_model.ormar_config.model_fields[related]
         target_field = cast("ForeignKeyField", target_field)
         reverse = False
         if target_field.virtual or target_field.is_multi:
@@ -473,14 +472,18 @@ class PrefetchQuery:
         select_related = []
         query_target = target_model
         table_prefix = ""
-        exclude_prefix = target_field.to.Meta.alias_manager.resolve_relation_alias(
-            from_model=target_field.owner, relation_name=target_field.name
+        exclude_prefix = (
+            target_field.to.ormar_config.alias_manager.resolve_relation_alias(
+                from_model=target_field.owner, relation_name=target_field.name
+            )
         )
         if target_field.is_multi:
             query_target = target_field.through
             select_related = [target_name]
-            table_prefix = target_field.to.Meta.alias_manager.resolve_relation_alias(
-                from_model=query_target, relation_name=target_name
+            table_prefix = (
+                target_field.to.ormar_config.alias_manager.resolve_relation_alias(
+                    from_model=query_target, relation_name=target_name
+                )
             )
             exclude_prefix = table_prefix
             self.already_extracted.setdefault(target_name, {})["prefix"] = table_prefix
diff --git a/ormar/queryset/queries/query.py b/ormar/queryset/queries/query.py
index de3821c..22c465e 100644
--- a/ormar/queryset/queries/query.py
+++ b/ormar/queryset/queries/query.py
@@ -1,4 +1,4 @@
-from typing import Dict, List, Optional, TYPE_CHECKING, Tuple, Type, Union
+from typing import TYPE_CHECKING, Dict, List, Optional, Tuple, Type, Union
 
 import sqlalchemy
 from sqlalchemy import Table, text
@@ -6,14 +6,14 @@ from sqlalchemy.sql import Join
 
 import ormar  # noqa I100
 from ormar.models.helpers.models import group_related_list
-from ormar.queryset.queries import FilterQuery, LimitQuery, OffsetQuery, OrderQuery
 from ormar.queryset.actions.filter_action import FilterAction
 from ormar.queryset.join import SqlJoin
+from ormar.queryset.queries import FilterQuery, LimitQuery, OffsetQuery, OrderQuery
 
 if TYPE_CHECKING:  # pragma no cover
     from ormar import Model
-    from ormar.queryset import OrderAction
     from ormar.models.excludable import ExcludableItems
+    from ormar.queryset import OrderAction
 
 
 class Query:
@@ -37,7 +37,7 @@ class Query:
         self.excludable = excludable
 
         self.model_cls = model_cls
-        self.table = self.model_cls.Meta.table
+        self.table = self.model_cls.ormar_config.table
 
         self.used_aliases: List[str] = []
 
@@ -75,10 +75,10 @@ class Query:
 
     def _apply_default_model_sorting(self) -> None:
         """
-        Applies orders_by from model Meta class (if provided), if it was not provided
-        it was filled by metaclass so it's always there and falls back to pk column
+        Applies orders_by from model OrmarConfig (if provided), if it was not provided
+        it was filled by metaclass, so it's always there and falls back to pk column
         """
-        for order_by in self.model_cls.Meta.orders_by:
+        for order_by in self.model_cls.ormar_config.orders_by:
             clause = ormar.OrderAction(order_str=order_by, model_cls=self.model_cls)
             self.sorted_orders[clause] = clause.get_text_clause()
 
@@ -97,7 +97,7 @@ class Query:
             and self._select_related
         )
 
-    def build_select_expression(self) -> Tuple[sqlalchemy.sql.select, List[str]]:
+    def build_select_expression(self) -> sqlalchemy.sql.select:
         """
         Main entry point from outside (after proper initialization).
 
@@ -113,7 +113,7 @@ class Query:
         self_related_fields = self.model_cls.own_table_columns(
             model=self.model_cls, excludable=self.excludable, use_alias=True
         )
-        self.columns = self.model_cls.Meta.alias_manager.prefixed_columns(
+        self.columns = self.model_cls.ormar_config.alias_manager.prefixed_columns(
             "", self.table, self_related_fields
         )
         self.apply_order_bys_for_primary_model()
@@ -179,7 +179,7 @@ class Query:
         The condition is added to filters to filter out desired number of main model
         primary key values. Whole query is used to determine the values.
         """
-        pk_alias = self.model_cls.get_column_alias(self.model_cls.Meta.pkname)
+        pk_alias = self.model_cls.get_column_alias(self.model_cls.ormar_config.pkname)
         pk_aliased_name = f"{self.table.name}.{pk_alias}"
         qry_text = sqlalchemy.text(f"{pk_aliased_name}")
         maxes = {}
diff --git a/ormar/queryset/queryset.py b/ormar/queryset/queryset.py
index c958729..0da47f5 100644
--- a/ormar/queryset/queryset.py
+++ b/ormar/queryset/queryset.py
@@ -1,19 +1,19 @@
 import asyncio
 from typing import (
+    TYPE_CHECKING,
     Any,
+    AsyncGenerator,
     Dict,
     Generic,
     List,
     Optional,
     Sequence,
     Set,
-    TYPE_CHECKING,
     Tuple,
     Type,
     TypeVar,
     Union,
     cast,
-    AsyncGenerator,
 )
 
 import databases
@@ -46,8 +46,8 @@ from ormar.queryset.reverse_alias_resolver import ReverseAliasResolver
 if TYPE_CHECKING:  # pragma no cover
     from ormar import Model
     from ormar.models import T
-    from ormar.models.metaclass import ModelMeta
     from ormar.models.excludable import ExcludableItems
+    from ormar.models.ormar_config import OrmarConfig
 else:
     T = TypeVar("T", bound="Model")
 
@@ -60,14 +60,14 @@ class QuerySet(Generic[T]):
     def __init__(  # noqa CFQ002
         self,
         model_cls: Optional[Type["T"]] = None,
-        filter_clauses: List = None,
-        exclude_clauses: List = None,
-        select_related: List = None,
-        limit_count: int = None,
-        offset: int = None,
-        excludable: "ExcludableItems" = None,
-        order_bys: List = None,
-        prefetch_related: List = None,
+        filter_clauses: Optional[List] = None,
+        exclude_clauses: Optional[List] = None,
+        select_related: Optional[List] = None,
+        limit_count: Optional[int] = None,
+        offset: Optional[int] = None,
+        excludable: Optional["ExcludableItems"] = None,
+        order_bys: Optional[List] = None,
+        prefetch_related: Optional[List] = None,
         limit_raw_sql: bool = False,
         proxy_source_model: Optional[Type["Model"]] = None,
     ) -> None:
@@ -84,16 +84,16 @@ class QuerySet(Generic[T]):
         self.limit_sql_raw = limit_raw_sql
 
     @property
-    def model_meta(self) -> "ModelMeta":
+    def model_config(self) -> "OrmarConfig":
         """
-        Shortcut to model class Meta set on QuerySet model.
+        Shortcut to model class OrmarConfig set on QuerySet model.
 
-        :return: Meta class of the model
-        :rtype: model Meta class
+        :return: OrmarConfig of the model
+        :rtype: model's OrmarConfig
         """
         if not self.model_cls:  # pragma nocover
             raise ValueError("Model class of QuerySet is not initialized")
-        return self.model_cls.Meta
+        return self.model_cls.ormar_config
 
     @property
     def model(self) -> Type["T"]:
@@ -109,15 +109,15 @@ class QuerySet(Generic[T]):
 
     def rebuild_self(  # noqa: CFQ002
         self,
-        filter_clauses: List = None,
-        exclude_clauses: List = None,
-        select_related: List = None,
-        limit_count: int = None,
-        offset: int = None,
-        excludable: "ExcludableItems" = None,
-        order_bys: List = None,
-        prefetch_related: List = None,
-        limit_raw_sql: bool = None,
+        filter_clauses: Optional[List] = None,
+        exclude_clauses: Optional[List] = None,
+        select_related: Optional[List] = None,
+        limit_count: Optional[int] = None,
+        offset: Optional[int] = None,
+        excludable: Optional["ExcludableItems"] = None,
+        order_bys: Optional[List] = None,
+        prefetch_related: Optional[List] = None,
+        limit_raw_sql: Optional[bool] = None,
         proxy_source_model: Optional[Type["Model"]] = None,
     ) -> "QuerySet":
         """
@@ -247,25 +247,28 @@ class QuerySet(Generic[T]):
     @property
     def database(self) -> databases.Database:
         """
-        Shortcut to models database from Meta class.
+        Shortcut to models database from OrmarConfig class.
 
         :return: database
         :rtype: databases.Database
         """
-        return self.model_meta.database
+        return self.model_config.database
 
     @property
     def table(self) -> sqlalchemy.Table:
         """
-        Shortcut to models table from Meta class.
+        Shortcut to models table from OrmarConfig.
 
         :return: database table
         :rtype: sqlalchemy.Table
         """
-        return self.model_meta.table
+        return self.model_config.table
 
     def build_select_expression(
-        self, limit: int = None, offset: int = None, order_bys: List = None
+        self,
+        limit: Optional[int] = None,
+        offset: Optional[int] = None,
+        order_bys: Optional[List] = None,
     ) -> sqlalchemy.sql.select:
         """
         Constructs the actual database query used in the QuerySet.
@@ -575,9 +578,11 @@ class QuerySet(Generic[T]):
             columns = [columns]
 
         orders_by = [
-            OrderAction(order_str=x, model_cls=self.model_cls)  # type: ignore
-            if not isinstance(x, OrderAction)
-            else x
+            (
+                OrderAction(order_str=x, model_cls=self.model_cls)  # type: ignore
+                if not isinstance(x, OrderAction)
+                else x
+            )
             for x in columns
         ]
 
@@ -586,7 +591,7 @@ class QuerySet(Generic[T]):
 
     async def values(
         self,
-        fields: Union[List, str, Set, Dict] = None,
+        fields: Union[List, str, Set, Dict, None] = None,
         exclude_through: bool = False,
         _as_dict: bool = True,
         _flatten: bool = False,
@@ -641,7 +646,7 @@ class QuerySet(Generic[T]):
 
     async def values_list(
         self,
-        fields: Union[List, str, Set, Dict] = None,
+        fields: Union[List, str, Set, Dict, None] = None,
         flatten: bool = False,
         exclude_through: bool = False,
     ) -> List:
@@ -702,7 +707,7 @@ class QuerySet(Generic[T]):
         expr = self.build_select_expression().alias("subquery_for_count")
         expr = sqlalchemy.func.count().select().select_from(expr)
         if distinct:
-            pk_column_name = self.model.get_column_alias(self.model_meta.pkname)
+            pk_column_name = self.model.get_column_alias(self.model_config.pkname)
             expr_distinct = expr.group_by(pk_column_name).alias("subquery_for_group")
             expr = sqlalchemy.func.count().select().select_from(expr_distinct)
         return await self.database.fetch_val(expr)
@@ -796,7 +801,7 @@ class QuerySet(Generic[T]):
             self.model.extract_related_names()
         )
         updates = {k: v for k, v in kwargs.items() if k in self_fields}
-        updates = self.model.validate_choices(updates)
+        updates = self.model.validate_enums(updates)
         updates = self.model.translate_columns_to_aliases(updates)
 
         expr = FilterQuery(filter_clauses=self.filter_clauses).apply(
@@ -855,7 +860,9 @@ class QuerySet(Generic[T]):
         query_offset = (page - 1) * page_size
         return self.rebuild_self(limit_count=limit_count, offset=query_offset)
 
-    def limit(self, limit_count: int, limit_raw_sql: bool = None) -> "QuerySet[T]":
+    def limit(
+        self, limit_count: int, limit_raw_sql: Optional[bool] = None
+    ) -> "QuerySet[T]":
         """
         You can limit the results to desired number of parent models.
 
@@ -872,7 +879,9 @@ class QuerySet(Generic[T]):
         limit_raw_sql = self.limit_sql_raw if limit_raw_sql is None else limit_raw_sql
         return self.rebuild_self(limit_count=limit_count, limit_raw_sql=limit_raw_sql)
 
-    def offset(self, offset: int, limit_raw_sql: bool = None) -> "QuerySet[T]":
+    def offset(
+        self, offset: int, limit_raw_sql: Optional[bool] = None
+    ) -> "QuerySet[T]":
         """
         You can also offset the results by desired number of main models.
 
@@ -908,7 +917,7 @@ class QuerySet(Generic[T]):
             order_bys=(
                 [
                     OrderAction(
-                        order_str=f"{self.model.Meta.pkname}",
+                        order_str=f"{self.model.ormar_config.pkname}",
                         model_cls=self.model_cls,  # type: ignore
                     )
                 ]
@@ -970,7 +979,7 @@ class QuerySet(Generic[T]):
                 order_bys=(
                     [
                         OrderAction(
-                            order_str=f"-{self.model.Meta.pkname}",
+                            order_str=f"-{self.model.ormar_config.pkname}",
                             model_cls=self.model_cls,  # type: ignore
                         )
                     ]
@@ -1027,7 +1036,7 @@ class QuerySet(Generic[T]):
         :return: updated or created model
         :rtype: Model
         """
-        pk_name = self.model_meta.pkname
+        pk_name = self.model_config.pkname
         if "pk" in kwargs:
             kwargs[pk_name] = kwargs.pop("pk")
         if pk_name not in kwargs or kwargs.get(pk_name) is None:
@@ -1093,7 +1102,7 @@ class QuerySet(Generic[T]):
 
         rows: list = []
         last_primary_key = None
-        pk_alias = self.model.get_column_alias(self.model_meta.pkname)
+        pk_alias = self.model.get_column_alias(self.model_config.pkname)
 
         async for row in self.database.iterate(query=expr):
             current_primary_key = row[pk_alias]
@@ -1144,7 +1153,7 @@ class QuerySet(Generic[T]):
 
         ready_objects = []
         for obj in objects:
-            ready_objects.append(obj.prepare_model_to_save(obj.dict()))
+            ready_objects.append(obj.prepare_model_to_save(obj.model_dump()))
             await asyncio.sleep(0)  # Allow context switching to prevent blocking
 
         # don't use execute_many, as in databases it's executed in a loop
@@ -1156,7 +1165,7 @@ class QuerySet(Generic[T]):
             obj.set_save_status(True)
 
     async def bulk_update(  # noqa:  CCR001
-        self, objects: List["T"], columns: List[str] = None
+        self, objects: List["T"], columns: Optional[List[str]] = None
     ) -> None:
         """
         Performs bulk update in one database session to speed up the process.
@@ -1179,7 +1188,7 @@ class QuerySet(Generic[T]):
             raise ModelListEmptyError("Bulk update objects are empty!")
 
         ready_objects = []
-        pk_name = self.model_meta.pkname
+        pk_name = self.model_config.pkname
         if not columns:
             columns = list(
                 self.model.extract_db_own_fields().union(
@@ -1193,7 +1202,7 @@ class QuerySet(Generic[T]):
         columns = [self.model.get_column_alias(k) for k in columns]
 
         for obj in objects:
-            new_kwargs = obj.dict()
+            new_kwargs = obj.model_dump()
             if new_kwargs.get(pk_name) is None:
                 raise ModelPersistenceError(
                     "You cannot update unsaved objects. "
@@ -1205,9 +1214,9 @@ class QuerySet(Generic[T]):
             )
             await asyncio.sleep(0)
 
-        pk_column = self.model_meta.table.c.get(self.model.get_column_alias(pk_name))
+        pk_column = self.model_config.table.c.get(self.model.get_column_alias(pk_name))
         pk_column_name = self.model.get_column_alias(pk_name)
-        table_columns = [c.name for c in self.model_meta.table.c]
+        table_columns = [c.name for c in self.model_config.table.c]
         expr = self.table.update().where(
             pk_column == bindparam("new_" + pk_column_name)
         )
@@ -1226,6 +1235,8 @@ class QuerySet(Generic[T]):
         for obj in objects:
             obj.set_save_status(True)
 
-        await cast(Type["Model"], self.model_cls).Meta.signals.post_bulk_update.send(
+        await cast(
+            Type["Model"], self.model_cls
+        ).ormar_config.signals.post_bulk_update.send(
             sender=self.model_cls, instances=objects  # type: ignore
         )
diff --git a/ormar/queryset/reverse_alias_resolver.py b/ormar/queryset/reverse_alias_resolver.py
index b9ed1c8..7cc4f8d 100644
--- a/ormar/queryset/reverse_alias_resolver.py
+++ b/ormar/queryset/reverse_alias_resolver.py
@@ -1,4 +1,4 @@
-from typing import Dict, List, TYPE_CHECKING, Type, cast
+from typing import TYPE_CHECKING, Dict, List, Type, cast
 
 if TYPE_CHECKING:  # pragma: no cover
     from ormar import ForeignKeyField, Model
@@ -20,7 +20,9 @@ class ReverseAliasResolver:
     ) -> None:
         self.select_related = select_related
         self.model_cls = model_cls
-        self.reversed_aliases = self.model_cls.Meta.alias_manager.reversed_aliases
+        self.reversed_aliases = (
+            self.model_cls.ormar_config.alias_manager.reversed_aliases
+        )
         self.excludable = excludable
         self.exclude_through = exclude_through
 
@@ -176,7 +178,7 @@ class ReverseAliasResolver:
             for relation in related_split:
                 previous_related_str = f"{related_str}__" if related_str else ""
                 new_related_str = previous_related_str + relation
-                field = model_cls.Meta.model_fields[relation]
+                field = model_cls.ormar_config.model_fields[relation]
                 field = cast("ForeignKeyField", field)
                 prefix_name = self._handle_through_fields_and_prefix(
                     model_cls=model_cls,
diff --git a/ormar/queryset/utils.py b/ormar/queryset/utils.py
index 4ebe07c..97122d8 100644
--- a/ormar/queryset/utils.py
+++ b/ormar/queryset/utils.py
@@ -1,20 +1,20 @@
 import collections.abc
 import copy
 from typing import (
+    TYPE_CHECKING,
     Any,
     Dict,
     List,
     Optional,
     Sequence,
     Set,
-    TYPE_CHECKING,
     Tuple,
     Type,
     Union,
 )
 
 if TYPE_CHECKING:  # pragma no cover
-    from ormar import Model, BaseField
+    from ormar import BaseField, Model
 
 
 def check_node_not_dict_or_not_last_node(
@@ -216,7 +216,7 @@ def extract_nested_models(  # noqa: CCR001
         child = getattr(model, related)
         if not child:
             continue
-        target_model = model_type.Meta.model_fields[related].to
+        target_model = model_type.ormar_config.model_fields[related].to
         if isinstance(child, list):
             extracted.setdefault(target_model.get_name(), []).extend(child)
             if select_dict[related] is not Ellipsis:
@@ -236,7 +236,7 @@ def extract_models_to_dict_of_lists(
     model_type: Type["Model"],
     models: Sequence["Model"],
     select_dict: Dict,
-    extracted: Dict = None,
+    extracted: Optional[Dict] = None,
 ) -> Dict:
     """
     Receives a list of models and extracts all of the children and their children
@@ -279,9 +279,9 @@ def get_relationship_alias_model_and_str(
     target_model = source_model
     previous_model = target_model
     previous_models = [target_model]
-    manager = target_model.Meta.alias_manager
+    manager = target_model.ormar_config.alias_manager
     for relation in related_parts[:]:
-        related_field = target_model.Meta.model_fields[relation]
+        related_field = target_model.ormar_config.model_fields[relation]
 
         if related_field.is_through:
             (previous_model, relation, is_through) = _process_through_field(
@@ -331,7 +331,7 @@ def _process_through_field(
     """
     is_through = True
     related_parts.remove(relation)
-    through_field = related_field.owner.Meta.model_fields[
+    through_field = related_field.owner.ormar_config.model_fields[
         related_field.related_name or ""
     ]
     if len(previous_models) > 1 and previous_models[-2] == through_field.to:
diff --git a/ormar/relations/__init__.py b/ormar/relations/__init__.py
index 4e4529b..15cc948 100644
--- a/ormar/relations/__init__.py
+++ b/ormar/relations/__init__.py
@@ -2,6 +2,7 @@
 Package handles relations on models, returning related models on calls and exposing
 QuerySetProxy for m2m and reverse relations.
 """
+
 from ormar.relations.alias_manager import AliasManager
 from ormar.relations.relation import Relation, RelationType
 from ormar.relations.relation_manager import RelationsManager
diff --git a/ormar/relations/alias_manager.py b/ormar/relations/alias_manager.py
index c8bd1a6..0355f34 100644
--- a/ormar/relations/alias_manager.py
+++ b/ormar/relations/alias_manager.py
@@ -1,15 +1,15 @@
 import string
 import uuid
 from random import choices
-from typing import Any, Dict, List, TYPE_CHECKING, Type, Union
+from typing import TYPE_CHECKING, Any, Dict, List, Optional, Type, Union
 
 import sqlalchemy
 from sqlalchemy import text
 
 if TYPE_CHECKING:  # pragma: no cover
     from ormar import Model
-    from ormar.models import ModelRow
     from ormar.fields import ForeignKeyField
+    from ormar.models import ModelRow
 
 
 def get_table_alias() -> str:
@@ -59,7 +59,7 @@ class AliasManager:
 
     @staticmethod
     def prefixed_columns(
-        alias: str, table: sqlalchemy.Table, fields: List = None
+        alias: str, table: sqlalchemy.Table, fields: Optional[List] = None
     ) -> List[text]:
         """
         Creates a list of aliases sqlalchemy text clauses from
@@ -106,7 +106,10 @@ class AliasManager:
         return self._prefixed_tables.setdefault(key, table.alias(full_alias))
 
     def add_relation_type(
-        self, source_model: Type["Model"], relation_name: str, reverse_name: str = None
+        self,
+        source_model: Type["Model"],
+        relation_name: str,
+        reverse_name: Optional[str] = None,
     ) -> None:
         """
         Registers the relations defined in ormar models.
@@ -134,7 +137,7 @@ class AliasManager:
         if parent_key not in self._aliases_new:
             self.add_alias(parent_key)
 
-        to_field = source_model.Meta.model_fields[relation_name]
+        to_field = source_model.ormar_config.model_fields[relation_name]
         child_model = to_field.to
         child_key = f"{child_model.get_name()}_{reverse_name}"
         if child_key not in self._aliases_new:
diff --git a/ormar/relations/querysetproxy.py b/ormar/relations/querysetproxy.py
index e61f862..1a767aa 100644
--- a/ormar/relations/querysetproxy.py
+++ b/ormar/relations/querysetproxy.py
@@ -1,6 +1,7 @@
-from _weakref import CallableProxyType
 from typing import (  # noqa: I100, I201
+    TYPE_CHECKING,
     Any,
+    AsyncGenerator,
     Dict,
     Generic,
     List,
@@ -8,23 +9,23 @@ from typing import (  # noqa: I100, I201
     Optional,
     Sequence,
     Set,
-    TYPE_CHECKING,
     Tuple,
     Type,
     TypeVar,
     Union,
     cast,
-    AsyncGenerator,
 )
 
+from _weakref import CallableProxyType
+
 import ormar  # noqa: I100, I202
 from ormar.exceptions import ModelPersistenceError, NoMatch, QueryDefinitionError
 
 if TYPE_CHECKING:  # pragma no cover
-    from ormar.relations import Relation
+    from ormar import OrderAction, RelationType
     from ormar.models import Model, T
     from ormar.queryset import QuerySet
-    from ormar import OrderAction, RelationType
+    from ormar.relations import Relation
 else:
     T = TypeVar("T", bound="Model")
 
@@ -43,17 +44,17 @@ class QuerysetProxy(Generic[T]):
         relation: "Relation",
         to: Type["T"],
         type_: "RelationType",
-        qryset: "QuerySet[T]" = None,
+        qryset: Optional["QuerySet[T]"] = None,
     ) -> None:
         self.relation: "Relation" = relation
         self._queryset: Optional["QuerySet[T]"] = qryset
         self.type_: "RelationType" = type_
         self._owner: Union[CallableProxyType, "Model"] = self.relation.manager.owner
-        self.related_field_name = self._owner.Meta.model_fields[
+        self.related_field_name = self._owner.ormar_config.model_fields[
             self.relation.field_name
         ].get_related_name()
         self.to: Type[T] = to
-        self.related_field = to.Meta.model_fields[self.related_field_name]
+        self.related_field = to.ormar_config.model_fields[self.related_field_name]
         self.owner_pk_value = self._owner.pk
         self.through_model_name = (
             self.related_field.through.get_name()
@@ -286,7 +287,9 @@ class QuerysetProxy(Generic[T]):
         return await queryset.delete(**kwargs)  # type: ignore
 
     async def values(
-        self, fields: Union[List, str, Set, Dict] = None, exclude_through: bool = False
+        self,
+        fields: Union[List, str, Set, Dict, None] = None,
+        exclude_through: bool = False,
     ) -> List:
         """
         Return a list of dictionaries with column values in order of the fields
@@ -308,7 +311,7 @@ class QuerysetProxy(Generic[T]):
 
     async def values_list(
         self,
-        fields: Union[List, str, Set, Dict] = None,
+        fields: Union[List, str, Set, Dict, None] = None,
         flatten: bool = False,
         exclude_through: bool = False,
     ) -> List:
@@ -551,7 +554,7 @@ class QuerysetProxy(Generic[T]):
         :return: updated or created model
         :rtype: Model
         """
-        pk_name = self.queryset.model_meta.pkname
+        pk_name = self.queryset.model_config.pkname
         if "pk" in kwargs:
             kwargs[pk_name] = kwargs.pop("pk")
         if pk_name not in kwargs or kwargs.get(pk_name) is None:
diff --git a/ormar/relations/relation.py b/ormar/relations/relation.py
index d73d627..7c2724d 100644
--- a/ormar/relations/relation.py
+++ b/ormar/relations/relation.py
@@ -1,10 +1,10 @@
 from enum import Enum
 from typing import (
+    TYPE_CHECKING,
     Generic,
     List,
     Optional,
     Set,
-    TYPE_CHECKING,
     Type,
     TypeVar,
     Union,
@@ -16,8 +16,8 @@ from ormar.exceptions import RelationshipInstanceError  # noqa I100
 from ormar.relations.relation_proxy import RelationProxy
 
 if TYPE_CHECKING:  # pragma no cover
-    from ormar.relations import RelationsManager
     from ormar.models import Model, NewBaseModel, T
+    from ormar.relations import RelationsManager
 else:
     T = TypeVar("T", bound="Model")
 
@@ -48,7 +48,7 @@ class Relation(Generic[T]):
         type_: RelationType,
         field_name: str,
         to: Type["T"],
-        through: Type["Model"] = None,
+        through: Optional[Type["Model"]] = None,
     ) -> None:
         """
         Initialize the Relation and keep the related models either as instances of
@@ -162,9 +162,17 @@ class Relation(Generic[T]):
                 rel = rel or []
                 if not isinstance(rel, list):
                     rel = [rel]
-                rel.append(child)
+                self._populate_owner_side_dict(rel=rel, child=child)
                 self._owner.__dict__[relation_name] = rel
 
+    def _populate_owner_side_dict(self, rel: List["Model"], child: "Model") -> None:
+        try:
+            if child not in rel:
+                rel.append(child)
+        except ReferenceError:
+            rel.clear()
+            rel.append(child)
+
     def remove(self, child: Union["NewBaseModel", Type["NewBaseModel"]]) -> None:
         """
         Removes child Model from relation, either sets None as related model or removes
diff --git a/ormar/relations/relation_manager.py b/ormar/relations/relation_manager.py
index e188bda..368661c 100644
--- a/ormar/relations/relation_manager.py
+++ b/ormar/relations/relation_manager.py
@@ -1,12 +1,12 @@
-from typing import Dict, List, Optional, Sequence, TYPE_CHECKING, Type, Union
+from typing import TYPE_CHECKING, Dict, List, Optional, Sequence, Type, Union
 from weakref import proxy
 
 from ormar.relations.relation import Relation, RelationType
 from ormar.relations.utils import get_relations_sides_and_names
 
 if TYPE_CHECKING:  # pragma no cover
-    from ormar.models import NewBaseModel, Model
-    from ormar.fields import ForeignKeyField, BaseField
+    from ormar.fields import BaseField, ForeignKeyField
+    from ormar.models import Model, NewBaseModel
 
 
 class RelationsManager:
@@ -16,7 +16,7 @@ class RelationsManager:
 
     def __init__(
         self,
-        related_fields: List["ForeignKeyField"] = None,
+        related_fields: Optional[List["ForeignKeyField"]] = None,
         owner: Optional["Model"] = None,
     ) -> None:
         self.owner = proxy(owner)
@@ -120,7 +120,7 @@ class RelationsManager:
         :param name: name of the relation
         :type name: str
         """
-        relation_name = item.Meta.model_fields[name].get_related_name()
+        relation_name = item.ormar_config.model_fields[name].get_related_name()
         item._orm.remove(name, parent)
         parent._orm.remove(relation_name, item)
 
diff --git a/ormar/relations/relation_proxy.py b/ormar/relations/relation_proxy.py
index 0169308..7efaf41 100644
--- a/ormar/relations/relation_proxy.py
+++ b/ormar/relations/relation_proxy.py
@@ -1,14 +1,15 @@
 from typing import (
+    TYPE_CHECKING,
     Any,
     Dict,
     Generic,
     List,
     Optional,
-    TYPE_CHECKING,
     Set,
     Type,
     TypeVar,
 )
+
 from typing_extensions import SupportsIndex
 
 import ormar
@@ -18,8 +19,8 @@ from ormar.relations.querysetproxy import QuerysetProxy
 if TYPE_CHECKING:  # pragma no cover
     from ormar import Model, RelationType
     from ormar.models import T
-    from ormar.relations import Relation
     from ormar.queryset import QuerySet
+    from ormar.relations import Relation
 else:
     T = TypeVar("T", bound="Model")
 
@@ -71,7 +72,7 @@ class RelationProxy(Generic[T], List[T]):
         """
         if self._related_field_name:
             return self._related_field_name
-        owner_field = self._owner.Meta.model_fields[self.field_name]
+        owner_field = self._owner.ormar_config.model_fields[self.field_name]
         self._related_field_name = owner_field.get_related_name()
 
         return self._related_field_name
@@ -245,7 +246,7 @@ class RelationProxy(Generic[T], List[T]):
         :rtype: QuerySet
         """
         related_field_name = self.related_field_name
-        pkname = self._owner.get_column_alias(self._owner.Meta.pkname)
+        pkname = self._owner.get_column_alias(self._owner.ormar_config.pkname)
         self._check_if_model_saved()
         kwargs = {f"{related_field_name}__{pkname}": self._owner.pk}
         queryset = (
diff --git a/ormar/signals/__init__.py b/ormar/signals/__init__.py
index 127fc2f..74a642c 100644
--- a/ormar/signals/__init__.py
+++ b/ormar/signals/__init__.py
@@ -1,7 +1,8 @@
 """
-Signals and SignalEmitter that gathers the signals on models Meta.
+Signals and SignalEmitter that gathers the signals on models OrmarConfig.
 Used to signal receivers functions about events, i.e. post_save, pre_delete etc.
 """
+
 from ormar.signals.signal import Signal, SignalEmitter
 
 __all__ = ["Signal", "SignalEmitter"]
diff --git a/ormar/signals/signal.py b/ormar/signals/signal.py
index 868b494..ee952d6 100644
--- a/ormar/signals/signal.py
+++ b/ormar/signals/signal.py
@@ -1,6 +1,6 @@
 import asyncio
 import inspect
-from typing import Any, Callable, Dict, TYPE_CHECKING, Tuple, Type, Union
+from typing import TYPE_CHECKING, Any, Callable, Dict, Tuple, Type, Union
 
 from ormar.exceptions import SignalDefinitionError
 
diff --git a/ormar/warnings.py b/ormar/warnings.py
new file mode 100644
index 0000000..318fd3c
--- /dev/null
+++ b/ormar/warnings.py
@@ -0,0 +1,51 @@
+# Adopted from pydantic
+from typing import Optional, Tuple
+
+
+class OrmarDeprecationWarning(DeprecationWarning):
+    """A Pydantic specific deprecation warning.
+
+    This warning is raised when using deprecated functionality in Ormar.
+    It provides information on when the deprecation was introduced and
+    the expected version in which the corresponding functionality will be removed.
+
+    Attributes:
+        message: Description of the warning
+        since: Ormar version in what the deprecation was introduced
+        expected_removal: Ormar version in what the functionality will be removed
+    """
+
+    message: str
+    since: Tuple[int, int]
+    expected_removal: Tuple[int, int]
+
+    def __init__(
+        self,
+        message: str,
+        *args: object,
+        since: Tuple[int, int],
+        expected_removal: Optional[Tuple[int, int]] = None,
+    ) -> None:  # pragma: no cover
+        super().__init__(message, *args)
+        self.message = message.rstrip(".")
+        self.since = since
+        self.expected_removal = (
+            expected_removal if expected_removal is not None else (since[0] + 1, 0)
+        )
+
+    def __str__(self) -> str:  # pragma: no cover
+        message = (
+            f"{self.message}. Deprecated in Ormar V{self.since[0]}.{self.since[1]}"
+            f" to be removed in V{self.expected_removal[0]}.{self.expected_removal[1]}."
+        )
+        if self.since == (0, 20):
+            message += " See Ormar V0.20 Migration Guide at https://collerek.github.io/ormar/migration/"
+        return message
+
+
+class OrmarDeprecatedSince020(OrmarDeprecationWarning):
+    """A specific `OrmarDeprecationWarning` subclass defining
+    functionality deprecated since Ormar 0.20."""
+
+    def __init__(self, message: str, *args: object) -> None:  # pragma: no cover
+        super().__init__(message, *args, since=(0, 20), expected_removal=(0, 30))
COLLAB_REFERENCE_PATCH_EOF
