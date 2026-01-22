## User details with optional fields

var has_accepted_terms: bool = false
var source: String = ""
var terms_agreement_version_id: int = 0
var privacy_agreement_version_id: int = 0


func _init(
	has_accepted_terms: bool = false,
	source: String = "",
	terms_agreement_version_id: int = 0,
	privacy_agreement_version_id: int = 0
) -> void:
	self.has_accepted_terms = has_accepted_terms
	self.source = source
	self.terms_agreement_version_id = terms_agreement_version_id
	self.privacy_agreement_version_id = privacy_agreement_version_id


func to_dict() -> Dictionary:
	var result: Dictionary = {}
	if has_accepted_terms:
		result["hasAcceptedTerms"] = has_accepted_terms
	if source != "":
		result["source"] = source
	if terms_agreement_version_id != 0:
		result["termsAgreementVersionId"] = terms_agreement_version_id
	if privacy_agreement_version_id != 0:
		result["privacyAgreementVersionId"] = privacy_agreement_version_id
	return result


static func from_dict(data: Dictionary):
	return load("res://addons/shipthis/models/user_details.gd").new(
		data.get("hasAcceptedTerms", false),
		data.get("source", ""),
		int(data.get("termsAgreementVersionId", 0)),
		int(data.get("privacyAgreementVersionId", 0))
	)
