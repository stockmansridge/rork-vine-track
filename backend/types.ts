/* eslint-disable */
// AUTO-GENERATED — DO NOT EDIT
// Run migrations to regenerate.

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      invitations: {
        Row: {
          created_at: string
          email: string
          id: string
          invited_by: string | null
          invited_by_name: string | null
          role: string
          status: string
          vineyard_id: string | null
          vineyard_name: string | null
        }
        Insert: {
          created_at?: string
          email: string
          id?: string
          invited_by?: string | null
          invited_by_name?: string | null
          role?: string
          status?: string
          vineyard_id?: string | null
          vineyard_name?: string | null
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          invited_by?: string | null
          invited_by_name?: string | null
          role?: string
          status?: string
          vineyard_id?: string | null
          vineyard_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "invitations_vineyard_id_fkey"
            columns: ["vineyard_id"]
            isOneToOne: false
            referencedRelation: "vineyards"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          email: string | null
          id: string
          is_admin: boolean
          name: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          id: string
          is_admin?: boolean
          name?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          id?: string
          is_admin?: boolean
          name?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      vineyard_data: {
        Row: {
          data: string
          data_type: string
          id: string
          updated_at: string
          vineyard_id: string
        }
        Insert: {
          data?: string
          data_type: string
          id: string
          updated_at?: string
          vineyard_id: string
        }
        Update: {
          data?: string
          data_type?: string
          id?: string
          updated_at?: string
          vineyard_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vineyard_data_vineyard_id_fkey"
            columns: ["vineyard_id"]
            isOneToOne: false
            referencedRelation: "vineyards"
            referencedColumns: ["id"]
          },
        ]
      }
      vineyard_members: {
        Row: {
          id: string
          joined_at: string
          name: string
          role: string
          user_id: string
          vineyard_id: string
        }
        Insert: {
          id?: string
          joined_at?: string
          name?: string
          role?: string
          user_id: string
          vineyard_id: string
        }
        Update: {
          id?: string
          joined_at?: string
          name?: string
          role?: string
          user_id?: string
          vineyard_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vineyard_members_vineyard_id_fkey"
            columns: ["vineyard_id"]
            isOneToOne: false
            referencedRelation: "vineyards"
            referencedColumns: ["id"]
          },
        ]
      }
      vineyards: {
        Row: {
          country: string | null
          created_at: string
          id: string
          logo_data: string | null
          name: string
          owner_id: string | null
        }
        Insert: {
          country?: string | null
          created_at?: string
          id?: string
          logo_data?: string | null
          name?: string
          owner_id?: string | null
        }
        Update: {
          country?: string | null
          created_at?: string
          id?: string
          logo_data?: string | null
          name?: string
          owner_id?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_invitation: {
        Args: { p_invitation_id: string }
        Returns: {
          created_at: string
          email: string
          id: string
          invited_by: string | null
          invited_by_name: string | null
          role: string
          status: string
          vineyard_id: string | null
          vineyard_name: string | null
        }
        SetofOptions: {
          from: "*"
          to: "invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      accept_pending_invitations_for_me: {
        Args: never
        Returns: {
          created_at: string
          email: string
          id: string
          invited_by: string | null
          invited_by_name: string | null
          role: string
          status: string
          vineyard_id: string | null
          vineyard_name: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "invitations"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      claim_vineyards_by_email: {
        Args: never
        Returns: {
          role: string
          vineyard_id: string
        }[]
      }
      create_invitation: {
        Args: { p_email: string; p_role: string; p_vineyard_id: string }
        Returns: {
          created_at: string
          email: string
          id: string
          invited_by: string | null
          invited_by_name: string | null
          role: string
          status: string
          vineyard_id: string | null
          vineyard_name: string | null
        }
        SetofOptions: {
          from: "*"
          to: "invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      get_my_pending_invitations: {
        Args: never
        Returns: {
          created_at: string
          email: string
          id: string
          invited_by: string
          invited_by_name: string
          role: string
          status: string
          vineyard_id: string
          vineyard_name: string
        }[]
      }
      get_my_vineyard_ids: {
        Args: never
        Returns: {
          vineyard_id: string
        }[]
      }
      get_my_vineyards_full: {
        Args: never
        Returns: {
          country: string
          created_at: string
          id: string
          logo_data: string
          name: string
          owner_id: string
        }[]
      }
      get_vinetrack_access_snapshot: { Args: never; Returns: Json }
      get_vineyard_members_with_email: {
        Args: { p_vineyard_id: string }
        Returns: {
          display_name: string
          email: string
          joined_at: string
          role: string
          user_id: string
        }[]
      }
      is_current_user_admin: { Args: never; Returns: boolean }
      is_vineyard_member: { Args: { p_vineyard_id: string }; Returns: boolean }
      is_vineyard_owner_or_manager: {
        Args: { p_vineyard_id: string }
        Returns: boolean
      }
      list_invitations_for_vineyard: {
        Args: { p_vineyard_id: string }
        Returns: {
          created_at: string
          email: string
          id: string
          invited_by: string | null
          invited_by_name: string | null
          role: string
          status: string
          vineyard_id: string | null
          vineyard_name: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "invitations"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      user_id: { Args: never; Returns: string }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
