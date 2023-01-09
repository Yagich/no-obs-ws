static func generate_enums(protocol_json_path: String, output_to_path: String) -> void:
	var protocol := FileAccess.open(protocol_json_path, FileAccess.READ).get_as_text()
	var protocol_json: Dictionary = JSON.parse_string(protocol)
	var res := "# This file is automatically generated, please do not change it. If you wish to edit it, check /addons/deckobsws/Utility/EnumGen.gd\n\n"
	for e in protocol_json.enums:
		# if all are deprecated, don't make the enum
		var deprecated_count: int
		for enumlet in e.enumIdentifiers:
			if enumlet.deprecated:
				deprecated_count += 1

		if deprecated_count == e.enumIdentifiers.size():
			continue

		res += "enum %s {\n" % e.enumType

		for enumlet in e.enumIdentifiers:
			var enumlet_value: int

			if !(enumlet.enumValue is String) || !("|" in enumlet.enumValue):
				enumlet_value = int(enumlet.enumValue)
			else:
				var enumlet_value_token: String = (enumlet.enumValue as String)\
					.substr(1)\
					.substr(0, enumlet.enumValue.length() - 2)
				var split := Array(enumlet_value_token.split("|")).map(
					func(x: String):
						return x.strip_edges()
				)

				var calculated_value: int
				for enum_partial in e.enumIdentifiers:
					if !(enum_partial.enumIdentifier) in split:
						continue

					calculated_value |= int(enum_partial.enumValue)

				enumlet_value = calculated_value

			res += "\t%s = %s,\n" % [
				(enumlet.enumIdentifier as String).to_snake_case().to_upper(),
				enumlet_value
				]

		res += "}\n\n\n"

	var result_file := FileAccess.open(output_to_path, FileAccess.WRITE)
	result_file.store_string(res.strip_edges() + "\n")