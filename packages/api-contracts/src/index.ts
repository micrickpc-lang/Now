export type LocationMode =
  | "NONE"
  | "CITY"
  | "DISTRICT"
  | "APPROXIMATE"
  | "EXACT_ROOM";
export type SignalState =
  | "DRAFT"
  | "ACTIVE"
  | "FULL"
  | "EXPIRED"
  | "CANCELLED"
  | "COMPLETED"
  | "MODERATED";

export interface ApiError {
  statusCode: number;
  error: string;
  message: string | string[];
  requestId?: string;
}

export interface RealtimeEnvelope<T> {
  id: string;
  sequence: number;
  occurredAt: string;
  payload: T;
}
