defmodule GraphLab.PatientMessaging do
  @moduledoc """
  The implementation of `GraphLab.Contracts.PatientMessaging`: the visit's messages, the
  policy that queues them, and the send.
  """

  use Boundary,
    deps: [EhOsContract, GraphLab.Contracts],
    exports: [VisitMessages, MessageThePatient, SendSms]
end
