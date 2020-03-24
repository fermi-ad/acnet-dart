/// Represents an ACNET status.
class Status {
  final int _val;

  /// Creates a new, ACNET status value. Both the facility and error code
  /// need to be specified.
  const Status({facility: int, errCode: int})
      : this._val = errCode * 256 + facility;

  /// Alternate constructor. This constructor is intended for code pulling
  /// status codes from network packets. For normal code -- and if one of the
  /// pre-defined error codes isn't sufficient -- the default constructor
  /// should be used.
  const Status.fromRaw(int v) : this._val = v;

  /// Returns the raw integer value of the status. Should only be used by
  /// code writing the status to a network buffer.
  int get raw => this._val;

  /// Returns the facility portion of the status.
  int get facility => this._val & 0xff;

  /// Returns the error code portion of the status.
  int get errCode => this._val ~/ 256;

  /// Returns true if the status represents "success".
  bool get isSuccess => this.errCode == 0;

  /// Returns true if the status represents "success", but contains additional
  /// information (i.e. could mean data was returned but it's "stale".)
  bool get isGood => this.errCode >= 0;

  /// Returns true is the status is bad. A bad status will shut down an ACNET
  /// request.
  bool get isBad => this.errCode < 0;

  /// Formats a status value into the canonical, Fermi format.
  String toString() {
    return "[${this._val & 255} ${this._val ~/ 256}]";
  }

  /// Defines an order to ACNET status values. Statuses are ordered first
  /// by facility and then by error code.
  int compareTo(Status o) {
    final fThis = this.facility;
    final fO = o.facility;

    return fThis == fO ? this.errCode - o.errCode : fThis - fO;
  }
}

// Pre-defined ACNET status codes as of Feb 18, 2020.

const Status ACNET_REPLY_TIMEOUT = const Status(facility: 1, errCode: 3);
const Status ACNET_ENDMULT = const Status(facility: 1, errCode: 2);
const Status ACNET_PEND = const Status(facility: 1, errCode: 1);
const Status ACNET_SUCCESS = const Status(facility: 1, errCode: 0);
const Status ACNET_RETRY = const Status(facility: 1, errCode: -1);
const Status ACNET_NOLCLMEM = const Status(facility: 1, errCode: -2);
const Status ACNET_NOREMMEM = const Status(facility: 1, errCode: -3);
const Status ACNET_RPLYPACK = const Status(facility: 1, errCode: -4);
const Status ACNET_REQPACK = const Status(facility: 1, errCode: -5);
const Status ACNET_REQTMO = const Status(facility: 1, errCode: -6);
const Status ACNET_QUEFULL = const Status(facility: 1, errCode: -7);
const Status ACNET_BUSY = const Status(facility: 1, errCode: -8);
const Status ACNET_NOT_CONNECTED = const Status(facility: 1, errCode: -21);
const Status ACNET_ARG = const Status(facility: 1, errCode: -22);
const Status ACNET_IVM = const Status(facility: 1, errCode: -23);
const Status ACNET_NO_SUCH = const Status(facility: 1, errCode: -24);
const Status ACNET_REQREJ = const Status(facility: 1, errCode: -25);
const Status ACNET_CANCELED = const Status(facility: 1, errCode: -26);
const Status ACNET_NAME_IN_USE = const Status(facility: 1, errCode: -27);
const Status ACNET_NCR = const Status(facility: 1, errCode: -28);
const Status ACNET_NONODE = const Status(facility: 1, errCode: -30);
const Status ACNET_TRUNC_REQUEST = const Status(facility: 1, errCode: -31);
const Status ACNET_TRUNC_REPLY = const Status(facility: 1, errCode: -32);
const Status ACNET_NO_TASK = const Status(facility: 1, errCode: -33);
const Status ACNET_DISCONNECTED = const Status(facility: 1, errCode: -34);
const Status ACNET_LEVEL2 = const Status(facility: 1, errCode: -35);
const Status ACNET_HARD_IO = const Status(facility: 1, errCode: -41);
const Status ACNET_NODE_DOWN = const Status(facility: 1, errCode: -42);
const Status ACNET_SYS = const Status(facility: 1, errCode: -43);
const Status ACNET_NXE = const Status(facility: 1, errCode: -44);
const Status ACNET_BUG = const Status(facility: 1, errCode: -45);
const Status ACNET_NE1 = const Status(facility: 1, errCode: -46);
const Status ACNET_NE2 = const Status(facility: 1, errCode: -47);
const Status ACNET_NE3 = const Status(facility: 1, errCode: -48);
const Status ACNET_UTIME = const Status(facility: 1, errCode: -49);
const Status ACNET_INVARG = const Status(facility: 1, errCode: -50);
const Status ACNET_MEMFAIL = const Status(facility: 1, errCode: -51);
const Status ACNET_NO_HANDLE = const Status(facility: 1, errCode: -52);
