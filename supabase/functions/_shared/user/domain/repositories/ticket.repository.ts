export abstract class TicketRepository {
    abstract getTicketById(id: number): Promise<any | null>;
}