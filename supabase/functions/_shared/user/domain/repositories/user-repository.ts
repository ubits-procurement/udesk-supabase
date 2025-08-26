export abstract class UserRepository {
  abstract getUserById(id: string): Promise<any | null>;
}