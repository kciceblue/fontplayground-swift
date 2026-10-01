import json

from jsonschema import Draft202012Validator

from fpengine.protocol import CAPABILITIES
from fpengine.protocol.errors import ErrorCode, FileErrorCode, Stage
from tests.protocol.conftest import SCHEMAS


def test_schemas_are_valid_draft_2020_12(schemas, registry):
    def refs(value, resolver):
        if isinstance(value, dict):
            if "$ref" in value:
                resolver.lookup(value["$ref"])
            for child in value.values():
                refs(child, resolver)
        elif isinstance(value, list):
            for child in value:
                refs(child, resolver)

    for name, schema in schemas.items():
        Draft202012Validator.check_schema(schema)
        assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
        assert schema["$id"].endswith(name)
        refs(schema, registry.resolver(schema["$id"]))


def test_examples_validate(schemas, registry, validator):
    types, commands = set(), set()
    examples = SCHEMAS / "examples"
    for path in examples.glob("*.jsonl"):
        for line in path.read_text().splitlines():
            event = json.loads(line)
            validator.validate(event)
            types.add(event["type"])
            if event["type"] == "result":
                commands.add(event["command"])
    assert types == {"hello", "progress", "face", "file_error", "result", "error"}
    assert commands == {"hello", "scan", "forge"}
    for path in examples.glob("*-request.json"):
        request_validator = Draft202012Validator(schemas[path.stem + ".schema.json"], registry=registry)
        request_validator.validate(json.loads(path.read_text()))


def test_enums_match_schemas(schemas):
    defs = schemas["defs.schema.json"]["$defs"]
    for enum, key in ((ErrorCode, "error_code"), (FileErrorCode, "file_error_code"), (Stage, "stage")):
        assert {member.value for member in enum} == set(defs[key]["enum"])
    Draft202012Validator(schemas["hello.schema.json"]["properties"]["capabilities"]).validate(list(CAPABILITIES))
