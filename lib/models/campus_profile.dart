class CampusProfile {
  const CampusProfile({
    required this.sid,
    required this.idCode,
    required this.studentName,
    required this.gradeName,
    required this.className,
    required this.academyName,
    required this.specialityName,
  });

  final String sid;
  final String idCode;
  final String studentName;
  final String gradeName;
  final String className;
  final String academyName;
  final String specialityName;

  factory CampusProfile.fromRemote(Map<String, dynamic> data) {
    return CampusProfile(
      sid: (data['SID'] ?? '').toString().trim(),
      idCode: (data['IDcode'] ?? '').toString().trim(),
      studentName: (data['StudentName'] ?? '').toString().trim(),
      gradeName: (data['GradeName'] ?? '').toString().trim(),
      className: (data['ClassName'] ?? '').toString().trim(),
      academyName: (data['AcademyName'] ?? '').toString().trim(),
      specialityName: (data['SpecialityName'] ?? '').toString().trim(),
    );
  }

  factory CampusProfile.fromJson(Map<String, dynamic> json) {
    return CampusProfile(
      sid: (json['sid'] ?? '').toString(),
      idCode: (json['idCode'] ?? '').toString(),
      studentName: (json['studentName'] ?? '').toString(),
      gradeName: (json['gradeName'] ?? '').toString(),
      className: (json['className'] ?? '').toString(),
      academyName: (json['academyName'] ?? '').toString(),
      specialityName: (json['specialityName'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sid': sid,
      'idCode': idCode,
      'studentName': studentName,
      'gradeName': gradeName,
      'className': className,
      'academyName': academyName,
      'specialityName': specialityName,
    };
  }
}
