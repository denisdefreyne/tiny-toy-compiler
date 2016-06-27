module Clarke
  module Phases
    class Generic
      def run(arr, mod, env)
        raise '???'
      end
    end

    class BuildEnv < Generic
      def run(arr)
        Clarke::Env.new.tap do |env|
          arr.each { |obj| run_single(obj, env) }
        end
      end

      private

      def run_single(obj, parent_env)
        case obj
        when Clarke::Nodes::FunDecl
          parent_env[obj.name] = obj
          obj.tenv = parent_env

        when Clarke::Nodes::FunDef
          parent_env[obj.name] =
            FunDecl.new(obj.name, obj.params.map(&:type), false, obj.return_type)
          obj.tenv = parent_env.push
          obj.params.each { |param| obj.tenv[param.name] = param }
          obj.body.each { |e| run_single(e, obj.tenv) }

        when Clarke::Nodes::Const
          obj.tenv = parent_env

        when Clarke::Nodes::Str
          obj.tenv = parent_env

        when Clarke::Nodes::VarRef
          obj.tenv = parent_env

        when Clarke::Nodes::OpAdd
          obj.tenv = parent_env
          run_single(obj.lhs, obj.tenv)
          run_single(obj.rhs, obj.tenv)

        when Clarke::Nodes::FunCall
          obj.tenv = parent_env
          obj.args.each do |arg|
            run_single(arg, obj.tenv)
          end

        when Clarke::Nodes::If
          obj.tenv = parent_env.push
          run_single(obj.condition, obj.tenv)
          true_env = obj.tenv.push
          obj.true_clause.each { |e| run_single(e, true_env) }
          false_env = obj.tenv.push
          obj.false_clause.each { |e| run_single(e, false_env) }

        else
          raise '???'

        end
      end
    end

    class LiftMain < Generic
      def run(arr, env)
        if env.key?('main')
          raise "Function `main` already defined"
        end

        stmts, exprs = arr.partition do |e|
          [FunDecl, FunDef].include?(e.class)
        end

        arr.replace(stmts)

        main = FunDef.new('main', [], Int32Type.instance, exprs).tap do |fun_decl|
          fun_decl.tenv = env
        end

        arr << main
        env['main'] = main
      end
    end

    class LiftFunDecls < Generic
      def run(arr, env)
        fun_decls = []
        fun_defs = []
        others = []
        arr.each do |e|
          case e
          when FunDecl
            fun_decls << e
          when FunDef
            fun_defs << e
          else
            others << e
          end
        end

        new_fun_decls =
          (fun_decls + fun_defs).map do |e|
            case e
            when Clarke::Nodes::FunDecl
              e
            when Clarke::Nodes::FunDef
              FunDecl.new(e.name, e.params.map(&:type), false, e.return_type).tap do |fun_decl|
                fun_decl.tenv = env
              end
            else
              raise '???'
            end
          end

        arr.replace(new_fun_decls + fun_defs + others)

        new_fun_decls.each do |e|
          env[e.name] = e
        end
      end
    end

    class Typecheck < Generic
      def run(arr)
        arr.each { |e| run_single(e) }
      end

      private

      def run_single(obj)
        case obj
        when FunDef
          unless run_single(obj.body.last) == Int32Type.instance
            raise 'last expr of function is not int32'
          end

        when Const
          obj.type

        when Str
          StringType.instance

        when VarRef
          obj.tenv.fetch(obj.name).type

        when OpAdd
          unless run_single(obj.lhs) == Int32Type.instance
            raise "type error: lhs is not int32"
          end
          unless run_single(obj.rhs) == Int32Type.instance
            raise "type error: rhs is not int32"
          end
          Int32Type.instance

        when FunCall
          obj.tenv.fetch(obj.name).return_type

        when If
          unless run_single(obj.true_clause.last) == Int32Type.instance
            raise "type error: true clause is not int32"
          end

          unless run_single(obj.false_clause.last) == Int32Type.instance
            raise "type error: false clause is not int32"
          end

          Int32Type.instance
        end
      end
    end

    class GenCode < Generic
      def run(arr, mod, env)
        arr.each { |e| e.gen_code(mod: mod, env: env, function: nil, builder: nil) }
      end
    end
  end
end
